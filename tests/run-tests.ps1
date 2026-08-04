[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$repoRoot = Split-Path -Parent $PSScriptRoot
$enginePath = Join-Path $repoRoot "scripts\graph-engine.js"
$behaviorScript = Join-Path $repoRoot "scripts\get-behavior.ps1"
$loggerScript = Join-Path $repoRoot "scripts\log-event.ps1"
$fixtureVault = Join-Path $PSScriptRoot "fixtures\vault"
$nodePath = (Get-Command node -ErrorAction Stop).Source

function Assert-Equal($Actual, $Expected, [string]$Message) {
    if ($Actual -ne $Expected) {
        throw "$Message. Expected '$Expected', got '$Actual'."
    }
}

function Invoke-GraphFixture([hashtable]$Request) {
    $requestJson = $Request | ConvertTo-Json -Depth 8 -Compress
    $requestBase64 = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes($requestJson)
    )
    $output = & $nodePath $enginePath $requestBase64 $fixtureVault 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Graph fixture failed: $($output -join "`n")"
    }
    return ($output -join "`n") | ConvertFrom-Json
}

$baseConfig = @{
    vaultPath = $fixtureVault
    excludedFolders = @(".obsidian/", ".trash/", ".git/")
    relationshipFields = @("Up", "Source", "References")
    frontmatterMapping = @{
        domain = "domain"
        source = "source"
        noteType = "type"
    }
}

$stats = Invoke-GraphFixture @{
    mode = "stats"
    config = $baseConfig
}
Assert-Equal $stats.totalNotes 5 "Fixture note count changed"
Assert-Equal $stats.totalLinks 3 "Fixture link count changed"
Assert-Equal $stats.orphanCount 2 "Fixture orphan count changed"
Assert-Equal $stats.unresolvedCount 1 "Fixture unresolved-link count changed"
Assert-Equal $stats._meta.backend "files" "Fixture must use the file backend"

$path = Invoke-GraphFixture @{
    mode = "path"
    from = "Alpha.md"
    to = "Folder/Gamma.md"
    config = $baseConfig
}
Assert-Equal $path.found $true "Expected fixture path was not found"
Assert-Equal $path.hops 1 "Unexpected shortest path length"

$bridges = Invoke-GraphFixture @{
    mode = "bridges"
    config = $baseConfig
}
Assert-Equal $bridges.totalBridges 0 "Triangle fixture should not contain bridges"

$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) (
    "obsidian-kb-tests-" + [guid]::NewGuid().ToString("N")
)
New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
try {
    foreach ($mode in @("on_demand", "auto", "audit")) {
        $configPath = Join-Path $tempRoot "$mode.json"
        @{
            behavior = @{
                mode = $mode
                log_retention_days = 7
            }
        } | ConvertTo-Json -Depth 4 |
            Set-Content -LiteralPath $configPath -Encoding UTF8
        $behavior = & $behaviorScript -ConfigPath $configPath | ConvertFrom-Json
        Assert-Equal $behavior.mode $mode "Behavior mode was not preserved"
        Assert-Equal $behavior.audit_logging ($mode -eq "audit") "Audit flag is incorrect"
        Assert-Equal $behavior.automatic_routing ($mode -ne "on_demand") "Routing flag is incorrect"
    }

    $logRoot = Join-Path $tempRoot "logs"
    & $loggerScript `
        -Query "server 10.20.30.40 password: do-not-store-this" `
        -Route search `
        -Reason "credential lookup" `
        -SearchStatus success `
        -RetentionDays 7 `
        -LogRoot $logRoot | Out-Null
    $logText = Get-Content -LiteralPath (
        Get-ChildItem -LiteralPath $logRoot -Filter "retrieval-*.jsonl" |
            Select-Object -First 1 -ExpandProperty FullName
    ) -Raw -Encoding UTF8
    if ($logText -match "10\.20\.30\.40" -or $logText -match "do-not-store-this") {
        throw "Logger redaction leaked fixture credentials."
    }

    $installTarget = Join-Path $tempRoot "installed-skill"
    $installScript = Join-Path $repoRoot "install.ps1"
    $install = & $installScript `
        -VaultPath $fixtureVault `
        -Agent custom `
        -TargetPath $installTarget `
        -SkipQmd | ConvertFrom-Json
    Assert-Equal $install.installed $true "One-command installation failed"
    Assert-Equal $install.search_backend "files" "Installer did not configure offline search"
    Assert-Equal $install.graph_backend "files" "Installer did not verify the file graph"
    if (-not (Test-Path -LiteralPath (Join-Path $installTarget "install.ps1") -PathType Leaf)) {
        throw "Installed Skill cannot run the one-command installer for upgrades."
    }

    $installedVaultScript = Join-Path $installTarget "scripts\vault.ps1"
    $context = & $installedVaultScript `
        -Mode context `
        -Query "Alpha" `
        -MaxResults 3 `
        -MaxRelated 5 `
        -Backend files | ConvertFrom-Json
    Assert-Equal $context.search_backend "files" "Context search did not use the offline fallback"
    Assert-Equal $context.hits[0].path "Alpha.md" "Context search missed the expected note"
    if (@($context.related.path) -notcontains "Beta.md") {
        throw "Context search did not expand the frontmatter relationship."
    }
    if (@($context.related.path) -notcontains "Folder/Gamma.md") {
        throw "Context search did not expand the body link relationship."
    }

    $doctor = & (Join-Path $installTarget "scripts\doctor.ps1") | ConvertFrom-Json
    Assert-Equal $doctor.healthy $true "Doctor rejected a valid one-command installation"

    $installedConfigPath = Join-Path $installTarget "config.json"
    $installedConfig = Get-Content -LiteralPath $installedConfigPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    $installedConfig.behavior.mode = "audit"
    $installedConfig | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $installedConfigPath -Encoding UTF8
    [void](& $installScript `
        -VaultPath $fixtureVault `
        -Agent custom `
        -TargetPath $installTarget `
        -SkipQmd | ConvertFrom-Json)
    $upgradedConfig = Get-Content -LiteralPath $installedConfigPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    Assert-Equal $upgradedConfig.behavior.mode "audit" "Upgrade discarded the user's behavior mode"

    # QMD 2.5.x can return qmd:// URIs whose folder punctuation differs from
    # the physical Vault path. Verify that the search adapter maps them back.
    $qmdFixtureVault = Join-Path $tempRoot "qmd-vault"
    New-Item -ItemType Directory -Path $qmdFixtureVault -Force | Out-Null
    Copy-Item -Path (Join-Path $fixtureVault "*") -Destination $qmdFixtureVault -Recurse
    Rename-Item `
        -LiteralPath (Join-Path $qmdFixtureVault "Folder") `
        -NewName "Folder_Name"
    $fakeQmd = Join-Path $tempRoot "fake-qmd.js"
    @'
const command = process.argv[2];
if (command === "update") process.exit(0);
if (command === "search") {
  process.stdout.write(JSON.stringify([{
    file: "qmd://mock/Folder-Name/Gamma.md",
    title: "Gamma",
    snippet: "Gamma",
    score: 1,
    line: 1
  }]));
  process.exit(0);
}
process.exit(1);
'@ | Set-Content -LiteralPath $fakeQmd -Encoding UTF8
    $upgradedConfig.vault_path = $qmdFixtureVault
    $upgradedConfig.qmd_executable = $nodePath
    $upgradedConfig.qmd_entry = $fakeQmd
    $upgradedConfig.qmd_collection = "mock"
    $upgradedConfig.search.backend = "qmd"
    $upgradedConfig | ConvertTo-Json -Depth 8 |
        Set-Content -LiteralPath $installedConfigPath -Encoding UTF8
    $qmdUriSearch = @(& $installedVaultScript `
        -Mode search `
        -Query "Gamma" `
        -MaxResults 1 | ConvertFrom-Json)
    Assert-Equal `
        $qmdUriSearch[0].path `
        "Folder_Name\Gamma.md" `
        "QMD virtual URI was not mapped back to the physical Vault path"
}
finally {
    if (Test-Path -LiteralPath $tempRoot) {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force
    }
}

$skillText = Get-Content -LiteralPath (Join-Path $repoRoot "SKILL.md") -Raw -Encoding UTF8
if ($skillText -notmatch "(?ms)^---\s+name:\s*obsidian-knowledge-base\s+description:.+?---") {
    throw "SKILL.md frontmatter is invalid."
}

Write-Host "All tests passed."
