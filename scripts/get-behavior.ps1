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

if (-not (Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw "Missing configuration file: $ConfigPath"
}

$config = Get-Content -LiteralPath $ConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$mode = [string]$config.behavior.mode
if ([string]::IsNullOrWhiteSpace($mode)) {
    $mode = "auto"
}
if ($mode -notin @("on_demand", "auto", "audit")) {
    throw "config.json behavior.mode must be one of: on_demand, auto, audit."
}

$retentionDays = 30
if ($null -ne $config.behavior.log_retention_days) {
    $retentionDays = [int]$config.behavior.log_retention_days
}
if ($retentionDays -lt 1 -or $retentionDays -gt 3650) {
    throw "config.json behavior.log_retention_days must be between 1 and 3650."
}

[ordered]@{
    mode = $mode
    automatic_routing = $mode -in @("auto", "audit")
    audit_logging = $mode -eq "audit"
    log_retention_days = $retentionDays
} | ConvertTo-Json -Compress
