[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$VaultPath,

    [ValidateSet("auto", "codex", "claude", "cursor", "agents", "custom")]
    [string]$Agent = "auto",

    [string]$TargetPath = "",

    [switch]$SkipQmd
)

$ErrorActionPreference = "Stop"
$sourceRoot = Split-Path -Parent $PSScriptRoot
$vault = [System.IO.Path]::GetFullPath($VaultPath)
if (-not (Test-Path -LiteralPath $vault -PathType Container)) {
    throw "Vault directory does not exist: $vault"
}
if (-not (Get-ChildItem -LiteralPath $vault -Recurse -File -Filter "*.md" | Select-Object -First 1)) {
    throw "Vault contains no Markdown notes: $vault"
}

function Resolve-AgentTarget {
    if (-not [string]::IsNullOrWhiteSpace($TargetPath)) {
        return [System.IO.Path]::GetFullPath($TargetPath)
    }
    if ($Agent -eq "custom") {
        throw "-TargetPath is required when -Agent custom is used."
    }

    $profileRoot = [Environment]::GetFolderPath("UserProfile")
    $targets = [ordered]@{
        codex = Join-Path $profileRoot ".codex\skills\obsidian-knowledge-base"
        claude = Join-Path $profileRoot ".claude\skills\obsidian-knowledge-base"
        cursor = Join-Path $profileRoot ".cursor\skills\obsidian-knowledge-base"
        agents = Join-Path $profileRoot ".agents\skills\obsidian-knowledge-base"
    }
    if ($Agent -ne "auto") { return $targets[$Agent] }

    foreach ($candidate in @("codex", "claude", "cursor", "agents")) {
        $parent = Split-Path -Parent $targets[$candidate]
        if (Test-Path -LiteralPath $parent -PathType Container) {
            return $targets[$candidate]
        }
    }
    return $targets.codex
}

$target = Resolve-AgentTarget
$nodeCommand = Get-Command node -ErrorAction SilentlyContinue
if ($null -eq $nodeCommand) {
    $winget = Get-Command winget -ErrorAction SilentlyContinue
    if ($null -eq $winget) {
        throw "Node.js 18+ is required and no supported package manager was found."
    }
    & $winget.Source install --id OpenJS.NodeJS.LTS --exact `
        --accept-package-agreements --accept-source-agreements
    if ($LASTEXITCODE -ne 0) { throw "Failed to install Node.js LTS with winget." }
    $nodeCandidate = Join-Path $env:ProgramFiles "nodejs\node.exe"
    if (Test-Path -LiteralPath $nodeCandidate -PathType Leaf) {
        $nodePath = $nodeCandidate
    }
    else {
        $nodeCommand = Get-Command node -ErrorAction SilentlyContinue
        if ($null -eq $nodeCommand) { throw "Node.js installed but node.exe was not found." }
        $nodePath = [System.IO.Path]::GetFullPath($nodeCommand.Source)
    }
}
else {
    $nodePath = [System.IO.Path]::GetFullPath($nodeCommand.Source)
}
$nodeVersionText = (& $nodePath --version).Trim().TrimStart("v")
if ([version]$nodeVersionText -lt [version]"18.0.0") {
    throw "Node.js 18 or newer is required; found $nodeVersionText."
}

$qmdEntry = ""
$qmdCollection = ""
$qmdStatus = "skipped"
if (-not $SkipQmd) {
    $npmCommand = Get-Command npm.cmd -ErrorAction SilentlyContinue
    if ($null -eq $npmCommand) { $npmCommand = Get-Command npm -ErrorAction SilentlyContinue }
    if ($null -eq $npmCommand) {
        $npmCandidate = Join-Path (Split-Path -Parent $nodePath) "npm.cmd"
        if (Test-Path -LiteralPath $npmCandidate -PathType Leaf) {
            $npmCommand = Get-Item -LiteralPath $npmCandidate
        }
    }
    if ($null -eq $npmCommand) { throw "npm was not found beside Node.js." }
    $npmRoot = (& $npmCommand.Source root -g).Trim()
    $qmdEntry = Join-Path $npmRoot "@tobilu\qmd\dist\cli\qmd.js"
    if (-not (Test-Path -LiteralPath $qmdEntry -PathType Leaf)) {
        & $npmCommand.Source install -g "@tobilu/qmd"
        if ($LASTEXITCODE -ne 0) { throw "Failed to install @tobilu/qmd." }
        $npmRoot = (& $npmCommand.Source root -g).Trim()
        $qmdEntry = Join-Path $npmRoot "@tobilu\qmd\dist\cli\qmd.js"
    }
    if (-not (Test-Path -LiteralPath $qmdEntry -PathType Leaf)) {
        throw "QMD installation completed but its entry point was not found."
    }

    $hash = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hashBytes = $hash.ComputeHash([Text.Encoding]::UTF8.GetBytes($vault.ToLowerInvariant()))
    }
    finally { $hash.Dispose() }
    $suffix = ([BitConverter]::ToString($hashBytes).Replace("-", "").Substring(0, 8)).ToLowerInvariant()
    $qmdCollection = "obsidian-$suffix"
    & $nodePath $qmdEntry collection add $vault --name $qmdCollection --mask "**/*.md" *> $null
    if ($LASTEXITCODE -ne 0) {
        # A deterministic collection name may already exist after an upgrade.
        $collections = (& $nodePath $qmdEntry collection list 2>&1 | Out-String)
        if ($collections -notmatch [regex]::Escape($qmdCollection)) {
            throw "Failed to create QMD collection '$qmdCollection'."
        }
    }
    & $nodePath $qmdEntry update *> $null
    if ($LASTEXITCODE -ne 0) { throw "Failed to update QMD indexes." }
    $qmdStatus = "ready"
}

$sourceFull = [System.IO.Path]::GetFullPath($sourceRoot).TrimEnd('\', '/')
$targetFull = [System.IO.Path]::GetFullPath($target).TrimEnd('\', '/')
$existingConfig = $null
$existingConfigPath = Join-Path $targetFull "config.json"
if (Test-Path -LiteralPath $existingConfigPath -PathType Leaf) {
    try {
        $existingConfig = Get-Content -LiteralPath $existingConfigPath -Raw -Encoding UTF8 |
            ConvertFrom-Json
    }
    catch {
        throw "The existing target config.json is invalid; repair or move it before reinstalling."
    }
}
if ($sourceFull -ne $targetFull) {
    New-Item -ItemType Directory -Path $targetFull -Force | Out-Null
    foreach ($item in @("SKILL.md", "README.md", "LICENSE", "config.example.json", "install.ps1")) {
        Copy-Item -LiteralPath (Join-Path $sourceFull $item) -Destination $targetFull -Force
    }
    foreach ($directory in @("agents", "scripts", "docs", "references")) {
        $destination = Join-Path $targetFull $directory
        New-Item -ItemType Directory -Path $destination -Force | Out-Null
        Copy-Item -Path (Join-Path $sourceFull "$directory\*") -Destination $destination -Recurse -Force
    }
}

$obsidianCli = @(
    (Get-Command obsidian -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -ErrorAction SilentlyContinue),
    "C:\Program Files\Obsidian\Obsidian.com",
    (Join-Path $env:LOCALAPPDATA "Obsidian\Obsidian.com")
) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
if (-not $obsidianCli -and $existingConfig.graph.obsidian_cli) {
    $obsidianCli = [string]$existingConfig.graph.obsidian_cli
}

$behaviorMode = "auto"
$retentionDays = 30
$graphBackend = "auto"
$excludedFolders = @(".obsidian/", ".trash/", ".git/", "attachments/", "templates/")
$relationshipFields = @("Up", "Source", "References", "来源", "参考", "应用于", "衍生自")
$frontmatterMapping = [ordered]@{ domain = "专业"; source = "来源"; noteType = "笔记类型" }
if ($null -ne $existingConfig) {
    if ([string]$existingConfig.behavior.mode -in @("on_demand", "auto", "audit")) {
        $behaviorMode = [string]$existingConfig.behavior.mode
    }
    if ([int]$existingConfig.behavior.log_retention_days -gt 0) {
        $retentionDays = [int]$existingConfig.behavior.log_retention_days
    }
    if ([string]$existingConfig.graph.backend -in @("auto", "obsidian", "files")) {
        $graphBackend = [string]$existingConfig.graph.backend
    }
    if (@($existingConfig.graph.excluded_folders).Count -gt 0) {
        $excludedFolders = @($existingConfig.graph.excluded_folders)
    }
    if (@($existingConfig.graph.relationship_fields).Count -gt 0) {
        $relationshipFields = @($existingConfig.graph.relationship_fields)
    }
    if ($null -ne $existingConfig.graph.frontmatter_mapping) {
        $frontmatterMapping = $existingConfig.graph.frontmatter_mapping
    }
}

$config = [ordered]@{
    config_version = 2
    vault_path = $vault
    # graph-engine.js also uses this Node executable when QMD is optional.
    qmd_executable = $nodePath
    qmd_entry = if ($qmdStatus -eq "ready") { $qmdEntry } else { "" }
    qmd_collection = $qmdCollection
    search = [ordered]@{ backend = "auto" }
    behavior = [ordered]@{ mode = $behaviorMode; log_retention_days = $retentionDays }
    graph = [ordered]@{
        backend = $graphBackend
        obsidian_cli = [string]$obsidianCli
        obsidian_vault = Split-Path -Leaf $vault
        excluded_folders = $excludedFolders
        relationship_fields = $relationshipFields
        frontmatter_mapping = $frontmatterMapping
    }
}
$configPath = Join-Path $targetFull "config.json"
$config | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $configPath -Encoding UTF8
[void](Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json)

$doctorJson = & (Join-Path $targetFull "scripts\doctor.ps1") -ConfigPath $configPath
$doctor = ($doctorJson -join "`n") | ConvertFrom-Json
if (-not $doctor.healthy) {
    throw "Installation completed but verification failed: $($doctorJson -join "`n")"
}

[ordered]@{
    installed = $true
    agent = $Agent
    skill_path = $targetFull
    vault_path = $vault
    node_version = $nodeVersionText
    search_backend = if ($qmdStatus -eq "ready") { "qmd with files fallback" } else { "files" }
    qmd = $qmdStatus
    graph_backend = [string]$doctor.graph_backend
    notes = [int]$doctor.note_count
    next_command = '.\scripts\vault.ps1 -Mode context -Query "your topic" -MaxResults 5'
} | ConvertTo-Json -Depth 5
