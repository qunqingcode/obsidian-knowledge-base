[CmdletBinding()]
param(
    [string]$ConfigPath = ""
)

$ErrorActionPreference = "Stop"
$skillRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
    $ConfigPath = Join-Path $skillRoot "config.json"
}
$ConfigPath = [System.IO.Path]::GetFullPath($ConfigPath)
$checks = [System.Collections.Generic.List[object]]::new()

function Add-Check([string]$Name, [bool]$Pass, [string]$Detail) {
    $checks.Add([pscustomobject]@{ name = $Name; pass = $Pass; detail = $Detail })
}

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    Add-Check "config" $false "missing"
    [ordered]@{ healthy = $false; checks = @($checks) } | ConvertTo-Json -Depth 5
    exit 1
}

try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
    Add-Check "config" $true "valid JSON"
}
catch {
    Add-Check "config" $false $_.Exception.Message
    [ordered]@{ healthy = $false; checks = @($checks) } | ConvertTo-Json -Depth 5
    exit 1
}

$vault = [string]$config.vault_path
$vaultReady = -not [string]::IsNullOrWhiteSpace($vault) -and (Test-Path -LiteralPath $vault -PathType Container)
Add-Check "vault" $vaultReady $(if ($vaultReady) { "available" } else { "missing" })

$node = Get-Command node -ErrorAction SilentlyContinue
Add-Check "node" ($null -ne $node) $(if ($node) { (& $node.Source --version).Trim() } else { "missing" })

$noteCount = 0
$graphBackend = "unavailable"
if ($vaultReady) {
    try {
        $listJson = & (Join-Path $PSScriptRoot "vault.ps1") -Mode list -MaxResults 1
        [void](($listJson -join "`n") | ConvertFrom-Json)
        $noteCount = @(Get-ChildItem -LiteralPath $vault -Recurse -File -Filter "*.md").Count
        Add-Check "read" $true "note listing works"
    }
    catch { Add-Check "read" $false $_.Exception.Message }

    try {
        $statsJson = & (Join-Path $PSScriptRoot "vault.ps1") -Mode stats -Backend files
        $stats = ($statsJson -join "`n") | ConvertFrom-Json
        $graphBackend = [string]$stats._meta.backend
        Add-Check "graph" $true "$graphBackend backend"
    }
    catch { Add-Check "graph" $false $_.Exception.Message }
}

$qmdReady = (
    -not [string]::IsNullOrWhiteSpace([string]$config.qmd_executable) -and
    -not [string]::IsNullOrWhiteSpace([string]$config.qmd_entry) -and
    (Test-Path -LiteralPath ([string]$config.qmd_executable) -PathType Leaf) -and
    (Test-Path -LiteralPath ([string]$config.qmd_entry) -PathType Leaf)
)
if ($vaultReady) {
    try {
        $searchJson = & (Join-Path $PSScriptRoot "vault.ps1") `
            -Mode search -Query "__obsidian_kb_doctor_probe__" -MaxResults 1
        [void](($searchJson -join "`n") | ConvertFrom-Json)
        Add-Check "search" $true $(if ($qmdReady) { "QMD preferred, files fallback verified" } else { "files fallback verified" })
    }
    catch { Add-Check "search" $false $_.Exception.Message }
}

$healthy = @($checks | Where-Object { -not $_.pass }).Count -eq 0
[ordered]@{
    healthy = $healthy
    config_path = $ConfigPath
    note_count = $noteCount
    graph_backend = $graphBackend
    checks = @($checks)
} | ConvertTo-Json -Depth 5
if (-not $healthy) { exit 1 }
