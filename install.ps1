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
& (Join-Path $PSScriptRoot "scripts\install.ps1") @PSBoundParameters
