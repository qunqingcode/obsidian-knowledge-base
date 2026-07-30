[CmdletBinding()]
param(
    [ValidateSet("route", "feedback")]
    [string]$EventType = "route",

    [string]$InteractionId = "",

    [AllowEmptyString()]
    [string]$Query = "",

    [ValidateSet("search", "no_search", "")]
    [string]$Route = "",

    [AllowEmptyString()]
    [string]$Reason = "",

    [ValidateSet("not_run", "success", "no_results", "timeout", "error", "")]
    [string]$SearchStatus = "",

    [ValidateRange(-1, 86400000)]
    [double]$LatencyMs = -1,

    [string]$CandidatesJson = "[]",

    [string[]]$UsedPaths = @(),

    [AllowEmptyString()]
    [string]$ErrorType = "",

    [switch]$Truncated,

    [switch]$Clarified,

    [switch]$InternalEntityMatch,

    [switch]$AmbiguousEntity,

    [switch]$UnauthorizedSensitiveRead,

    [switch]$NoteInstructionAffected,

    [ValidateSet("search", "no_search", "")]
    [string]$GroundTruthRoute = "",

    [ValidateSet("relevant", "irrelevant", "mixed", "unknown")]
    [string]$EvidenceLabel = "unknown",

    [ValidateRange(0, 3650)]
    [int]$RetentionDays = 0,

    [string]$LogRoot = ""
)

$ErrorActionPreference = "Stop"
$skillRoot = Split-Path -Parent $PSScriptRoot
if ($RetentionDays -eq 0) {
    $RetentionDays = 30
    $configPath = Join-Path $skillRoot "config.json"
    if (Test-Path -LiteralPath $configPath -PathType Leaf) {
        $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -ne $config.behavior.log_retention_days) {
            $RetentionDays = [int]$config.behavior.log_retention_days
        }
    }
}
if ($RetentionDays -lt 1 -or $RetentionDays -gt 3650) {
    throw "RetentionDays must be between 1 and 3650."
}
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $skillRoot "logs"
}
$logRoot = [System.IO.Path]::GetFullPath($LogRoot)

function Protect-LogText([string]$Value) {
    if ([string]::IsNullOrEmpty($Value)) {
        return $Value
    }

    $redacted = $Value
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)\b(bearer)\s+[A-Za-z0-9._~+/\-=]+',
        '$1 [REDACTED]'
    )
    $redacted = [regex]::Replace(
        $redacted,
        '(?i)(password|passwd|pwd|token|secret|api[\s_-]*key|access[\s_-]*key|账号|账户|用户名|密码|口令|令牌|密钥)\s*(?:是|为|[:=：])\s*[^\s,;，；]+',
        '$1=[REDACTED]'
    )
    $redacted = [regex]::Replace(
        $redacted,
        '(?<![\d.])(?:25[0-5]|2[0-4]\d|1?\d?\d)(?:\.(?:25[0-5]|2[0-4]\d|1?\d?\d)){3}(?![\d.])',
        '[REDACTED_IP]'
    )
    $redacted = [regex]::Replace(
        $redacted,
        '(?<![A-Za-z0-9])[A-Za-z0-9_\-]{32,}(?![A-Za-z0-9])',
        '[REDACTED_SECRET]'
    )
    return $redacted
}

if ([string]::IsNullOrWhiteSpace($InteractionId)) {
    $InteractionId = [guid]::NewGuid().ToString()
}

$rawCandidates = @()
if (-not [string]::IsNullOrWhiteSpace($CandidatesJson)) {
    $parsed = $CandidatesJson | ConvertFrom-Json
    if ($null -ne $parsed) {
        $rawCandidates = @($parsed)
    }
}

$candidates = @(
    for ($index = 0; $index -lt [Math]::Min(5, $rawCandidates.Count); $index++) {
        $candidate = $rawCandidates[$index]
        [ordered]@{
            path = [string]$candidate.path
            rank = $index + 1
            score = if ($null -eq $candidate.score) { $null } else { [double]$candidate.score }
            sensitive = [bool]$candidate.sensitive
            modified = [string]$candidate.modified
            used = [string]$candidate.path -in $UsedPaths
        }
    }
)

$event = [ordered]@{
    timestamp = [DateTimeOffset]::Now.ToString("o")
    interaction_id = $InteractionId
    event_type = $EventType
    query_redacted = Protect-LogText $Query
    route = $Route
    route_reason = Protect-LogText $Reason
    search_status = $SearchStatus
    latency_ms = if ($LatencyMs -lt 0) { $null } else { $LatencyMs }
    candidates = $candidates
    used_paths = @($UsedPaths)
    error_type = Protect-LogText $ErrorType
    truncated = [bool]$Truncated
    clarified = [bool]$Clarified
    internal_entity_match = [bool]$InternalEntityMatch
    ambiguous_entity = [bool]$AmbiguousEntity
    unauthorized_sensitive_read = [bool]$UnauthorizedSensitiveRead
    note_instruction_affected = [bool]$NoteInstructionAffected
    ground_truth_route = $GroundTruthRoute
    evidence_label = $EvidenceLabel
}

New-Item -ItemType Directory -Path $logRoot -Force | Out-Null

$cutoff = (Get-Date).Date.AddDays(-$RetentionDays)
Get-ChildItem -LiteralPath $logRoot -File -Filter "retrieval-*.jsonl" |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    ForEach-Object { Remove-Item -LiteralPath $_.FullName -Force }

$logPath = Join-Path $logRoot ("retrieval-{0}.jsonl" -f (Get-Date -Format "yyyy-MM-dd"))
$jsonLine = ($event | ConvertTo-Json -Depth 6 -Compress) + [Environment]::NewLine
$bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($jsonLine)

$lastError = $null
for ($attempt = 1; $attempt -le 5; $attempt++) {
    try {
        $stream = [System.IO.FileStream]::new(
            $logPath,
            [System.IO.FileMode]::Append,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::Read
        )
        try {
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        }
        finally {
            $stream.Dispose()
        }
        $lastError = $null
        break
    }
    catch {
        $lastError = $_
        Start-Sleep -Milliseconds (40 * $attempt)
    }
}

if ($null -ne $lastError) {
    throw "Failed to append retrieval evaluation log: $($lastError.Exception.Message)"
}

[pscustomobject]@{
    interaction_id = $InteractionId
    log_path = $logPath
} | ConvertTo-Json -Compress
