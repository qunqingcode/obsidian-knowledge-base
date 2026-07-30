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
