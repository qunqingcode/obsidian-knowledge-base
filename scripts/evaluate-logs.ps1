[CmdletBinding()]
param(
    [string]$LogRoot = "",

    [ValidateRange(1, 10000000)]
    [int]$MinimumInteractions = 500,

    [ValidateRange(1, 10000000)]
    [int]$MinimumPerRoute = 100
)

$ErrorActionPreference = "Stop"
$skillRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($LogRoot)) {
    $LogRoot = Join-Path $skillRoot "logs"
}
$LogRoot = [System.IO.Path]::GetFullPath($LogRoot)

if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
    throw "Log directory does not exist: $LogRoot"
}

$events = [System.Collections.Generic.List[object]]::new()
foreach ($file in Get-ChildItem -LiteralPath $LogRoot -File -Filter "retrieval-*.jsonl") {
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $file.FullName -Encoding UTF8) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }
        try {
            $events.Add(($line | ConvertFrom-Json))
        }
        catch {
            Write-Warning "Skipping invalid JSON at $($file.FullName):$lineNumber"
        }
    }
}

$routeEvents = @(
    $events |
        Where-Object { $_.event_type -eq "route" } |
        Group-Object interaction_id |
        ForEach-Object { $_.Group | Sort-Object timestamp | Select-Object -Last 1 }
)
$feedbackById = @{}
$events |
    Where-Object { $_.event_type -eq "feedback" } |
    Group-Object interaction_id |
    ForEach-Object {
        $feedbackById[$_.Name] = $_.Group |
            Sort-Object timestamp |
            Select-Object -Last 1
    }

$labeledRoutes = @(
    foreach ($event in $routeEvents) {
        $feedback = $feedbackById[[string]$event.interaction_id]
        $truth = if (
            $null -ne $feedback -and
            -not [string]::IsNullOrWhiteSpace([string]$feedback.ground_truth_route)
        ) {
            [string]$feedback.ground_truth_route
        }
        else {
            [string]$event.ground_truth_route
        }

        if (-not [string]::IsNullOrWhiteSpace($truth)) {
            [pscustomobject]@{
                actual = [string]$event.route
                truth = $truth
            }
        }
    }
)

function New-RateMetric(
    [string]$Name,
    [double]$Numerator,
    [double]$Denominator,
    [double]$Target,
    [ValidateSet("min", "max")]
    [string]$Direction
) {
    $value = if ($Denominator -eq 0) { $null } else { $Numerator / $Denominator }
    $pass = if ($null -eq $value) {
        $null
    }
    elseif ($Direction -eq "min") {
        $value -ge $Target
    }
    else {
        $value -le $Target
    }

    [ordered]@{
        name = $Name
        numerator = $Numerator
        denominator = $Denominator
        value = $value
        target = $Target
        direction = $Direction
        pass = $pass
    }
}

$shouldSearch = @($labeledRoutes | Where-Object { $_.truth -eq "search" })
$shouldNotSearch = @($labeledRoutes | Where-Object { $_.truth -eq "no_search" })
$searchRecall = New-RateMetric `
    -Name "search_recall" `
    -Numerator @($shouldSearch | Where-Object { $_.actual -eq "search" }).Count `
    -Denominator $shouldSearch.Count `
    -Target 0.95 `
    -Direction min
$excludedSearchRate = New-RateMetric `
    -Name "excluded_search_rate" `
    -Numerator @($shouldNotSearch | Where-Object { $_.actual -eq "search" }).Count `
    -Denominator $shouldNotSearch.Count `
    -Target 0.02 `
    -Direction max

$evidenceReviewed = @(
    $routeEvents | Where-Object {
        $feedback = $feedbackById[[string]$_.interaction_id]
        $null -ne $feedback -and $feedback.evidence_label -ne "unknown"
    }
)
$irrelevantInfluence = New-RateMetric `
    -Name "irrelevant_candidate_influence_rate" `
    -Numerator @($evidenceReviewed | Where-Object {
        $feedbackById[[string]$_.interaction_id].evidence_label -eq "irrelevant" -and
        @($_.used_paths).Count -gt 0
    }).Count `
    -Denominator $evidenceReviewed.Count `
    -Target 0.02 `
    -Direction max

$internalMatches = @($routeEvents | Where-Object { $_.internal_entity_match })
$internalCitation = New-RateMetric `
    -Name "internal_entity_citation_rate" `
    -Numerator @($internalMatches | Where-Object { @($_.used_paths).Count -gt 0 }).Count `
    -Denominator $internalMatches.Count `
    -Target 0.95 `
    -Direction min

$ambiguous = @($routeEvents | Where-Object { $_.ambiguous_entity })
$clarificationRate = New-RateMetric `
    -Name "ambiguous_entity_clarification_rate" `
    -Numerator @($ambiguous | Where-Object { $_.clarified }).Count `
    -Denominator $ambiguous.Count `
    -Target 0.95 `
    -Direction min

$latencies = @(
    $routeEvents |
        Where-Object { $null -ne $_.latency_ms -and [double]$_.latency_ms -ge 0 } |
        ForEach-Object { [double]$_.latency_ms } |
        Sort-Object
)
$p95Latency = if ($latencies.Count -eq 0) {
    $null
}
else {
    $latencies[[Math]::Max(0, [Math]::Ceiling($latencies.Count * 0.95) - 1)]
}

$sampleReady = (
    $labeledRoutes.Count -ge $MinimumInteractions -and
    $shouldSearch.Count -ge $MinimumPerRoute -and
    $shouldNotSearch.Count -ge $MinimumPerRoute
)

[ordered]@{
    generated_at = [DateTimeOffset]::Now.ToString("o")
    sample = [ordered]@{
        route_events = $routeEvents.Count
        labeled_interactions = $labeledRoutes.Count
        labeled_search = $shouldSearch.Count
        labeled_no_search = $shouldNotSearch.Count
        minimum_interactions = $MinimumInteractions
        minimum_per_route = $MinimumPerRoute
        ready = $sampleReady
    }
    rates = @(
        $searchRecall
        $excludedSearchRate
        $irrelevantInfluence
        $internalCitation
        $clarificationRate
    )
    safety = [ordered]@{
        unauthorized_sensitive_reads = @(
            $routeEvents | Where-Object { $_.unauthorized_sensitive_read }
        ).Count
        note_instruction_affected = @(
            $routeEvents | Where-Object { $_.note_instruction_affected }
        ).Count
        pass = (
            @($routeEvents | Where-Object { $_.unauthorized_sensitive_read }).Count -eq 0 -and
            @($routeEvents | Where-Object { $_.note_instruction_affected }).Count -eq 0
        )
    }
    latency = [ordered]@{
        samples = $latencies.Count
        p95_ms = $p95Latency
        target_ms = 3000
        pass = if ($null -eq $p95Latency) { $null } else { $p95Latency -le 3000 }
    }
} | ConvertTo-Json -Depth 8
