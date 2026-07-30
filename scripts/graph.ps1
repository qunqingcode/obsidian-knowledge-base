[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "links", "backlinks", "neighbors", "path", "cluster", "bridges",
        "hubs", "orphans", "relations", "stats", "unresolved",
        "suggest-links", "health", "report"
    )]
    [string]$Mode,

    [string]$Note = "",
    [string]$From = "",
    [string]$To = "",

    [ValidateRange(1, 5)]
    [int]$Depth = 2,

    [ValidateRange(1, 100)]
    [int]$Top = 20,

    [string]$Folder = "",

    [ValidateRange(1, 500)]
    [int]$MaxResults = 100,

    [ValidateRange(1, 100)]
    [int]$MaxSuggestions = 30,

    [ValidateSet("auto", "obsidian", "files")]
    [string]$Backend = "auto"
)

$ErrorActionPreference = "Stop"
$skillRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $skillRoot "config.json"
$enginePath = Join-Path $PSScriptRoot "graph-engine.js"

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Missing configuration file: $configPath"
}
if (-not (Test-Path -LiteralPath $enginePath -PathType Leaf)) {
    throw "Missing graph engine: $enginePath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
$vaultPath = [System.IO.Path]::GetFullPath([string]$config.vault_path)
if (-not (Test-Path -LiteralPath $vaultPath -PathType Container)) {
    throw "Configured Obsidian vault does not exist: $vaultPath"
}

$excludedFolders = @($config.graph.excluded_folders)
if ($excludedFolders.Count -eq 0) {
    $excludedFolders = @(".obsidian/", ".trash/", ".git/")
}
$relationshipFields = @($config.graph.relationship_fields)
if ($relationshipFields.Count -eq 0) {
    $relationshipFields = @("Up", "Source", "References", "来源", "参考", "应用于", "衍生自")
}
$frontmatterMapping = $config.graph.frontmatter_mapping
if ($null -eq $frontmatterMapping) {
    $frontmatterMapping = [pscustomobject]@{
        domain = "专业"
        source = "来源"
        noteType = "笔记类型"
    }
}

$request = [ordered]@{
    mode = $Mode
    note = $Note.Replace("\", "/")
    from = $From.Replace("\", "/")
    to = $To.Replace("\", "/")
    depth = $Depth
    top = $Top
    folder = $Folder.Replace("\", "/")
    maxResults = $MaxResults
    maxSuggestions = $MaxSuggestions
    config = [ordered]@{
        vaultPath = $vaultPath
        excludedFolders = $excludedFolders
        relationshipFields = $relationshipFields
        frontmatterMapping = $frontmatterMapping
    }
}

$requestJson = ConvertTo-Json -InputObject $request -Depth 8 -Compress
$requestBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($requestJson))

function Test-ObsidianCli {
    param([string]$CliPath)
    if ([string]::IsNullOrWhiteSpace($CliPath) -or -not (Test-Path -LiteralPath $CliPath -PathType Leaf)) {
        return $false
    }
    $output = (& $CliPath version 2>&1 | Out-String)
    return $LASTEXITCODE -eq 0 -and $output -notmatch "not enabled"
}

function Invoke-ObsidianBackend {
    $cliPath = [System.IO.Path]::GetFullPath([string]$config.graph.obsidian_cli)
    $vaultName = [string]$config.graph.obsidian_vault
    if ([string]::IsNullOrWhiteSpace($vaultName)) {
        throw "config.json graph.obsidian_vault must be configured for the Obsidian backend."
    }

    $engineJsPath = $enginePath.Replace("\", "/").Replace("'", "\'")
    $evalCode = "globalThis.__obsidianGraphRequest=JSON.parse(Buffer.from('$requestBase64','base64').toString('utf8'));eval(require('fs').readFileSync('$engineJsPath','utf8'))"
    $output = & $cliPath ("vault=" + $vaultName) "eval" ("code=" + $evalCode) 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Obsidian graph query failed: $($output -join "`n")"
    }
    $text = ($output -join "`n").Trim()
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "Obsidian graph query returned no output."
    }
    ($text -replace "^\s*=>\s*", "")
}

function Invoke-FileBackend {
    $nodePath = [System.IO.Path]::GetFullPath([string]$config.qmd_executable)
    if (-not (Test-Path -LiteralPath $nodePath -PathType Leaf)) {
        throw "Node.js executable does not exist: $nodePath"
    }
    $output = & $nodePath $enginePath $requestBase64 $vaultPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "File graph query failed: $($output -join "`n")"
    }
    ($output -join "`n").Trim()
}

$configuredCli = [string]$config.graph.obsidian_cli
$cliReady = Test-ObsidianCli -CliPath $configuredCli

if ($Backend -eq "obsidian" -and -not $cliReady) {
    throw "Obsidian CLI is unavailable or disabled. Enable Settings > General > Advanced > Command-line interface, or use -Backend files."
}

if ($Backend -eq "obsidian" -or ($Backend -eq "auto" -and $cliReady)) {
    Invoke-ObsidianBackend
} else {
    Invoke-FileBackend
}
