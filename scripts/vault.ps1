[CmdletBinding()]
param(
    [ValidateSet(
        "search", "list", "read", "read-json",
        "links", "backlinks", "neighbors", "path", "cluster", "bridges",
        "hubs", "orphans", "relations", "stats", "unresolved",
        "suggest-links", "health", "report"
    )]
    [string]$Mode = "search",

    [string]$Query = "",

    [string]$Note = "",

    [string]$From = "",

    [string]$To = "",

    [ValidateRange(1, 5)]
    [int]$Depth = 2,

    [ValidateRange(1, 100)]
    [int]$Top = 20,

    [string]$Folder = "",

    [ValidateRange(1, 500)]
    [int]$MaxResults = 20,

    [ValidateRange(0, 5)]
    [int]$ContextLines = 1,

    [ValidateRange(1, 200000)]
    [int]$MaxChars = 20000,

    [switch]$AllowSensitive,

    [ValidateRange(1, 100)]
    [int]$MaxSuggestions = 30,

    [ValidateSet("auto", "obsidian", "files")]
    [string]$Backend = "auto"
)

$ErrorActionPreference = "Stop"
$skillRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $skillRoot "config.json"

if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
    throw "Missing configuration file: $configPath"
}

$config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($config.vault_path)) {
    throw "config.json must contain a non-empty vault_path."
}

$vault = [System.IO.Path]::GetFullPath([string]$config.vault_path)
if (-not (Test-Path -LiteralPath $vault -PathType Container)) {
    throw "Configured Obsidian vault does not exist: $vault"
}

$qmdExecutable = [string]$config.qmd_executable
if ([string]::IsNullOrWhiteSpace($qmdExecutable)) {
    throw "config.json must contain a non-empty qmd_executable."
}
$qmdExecutable = [System.IO.Path]::GetFullPath($qmdExecutable)
if (-not (Test-Path -LiteralPath $qmdExecutable -PathType Leaf)) {
    throw "Configured QMD executable does not exist: $qmdExecutable"
}

$qmdEntry = [string]$config.qmd_entry
if ([string]::IsNullOrWhiteSpace($qmdEntry)) {
    throw "config.json must contain a non-empty qmd_entry."
}
$qmdEntry = [System.IO.Path]::GetFullPath($qmdEntry)
if (-not (Test-Path -LiteralPath $qmdEntry -PathType Leaf)) {
    throw "Configured QMD entry point does not exist: $qmdEntry"
}

$qmdCollection = [string]$config.qmd_collection
if ([string]::IsNullOrWhiteSpace($qmdCollection)) {
    throw "config.json must contain a non-empty qmd_collection."
}

$vaultPrefix = $vault.TrimEnd(
    [System.IO.Path]::DirectorySeparatorChar,
    [System.IO.Path]::AltDirectorySeparatorChar
) + [System.IO.Path]::DirectorySeparatorChar

function Get-VaultNotes {
    Get-ChildItem -LiteralPath $vault -Recurse -File -Filter "*.md" |
        Where-Object {
            $relative = $_.FullName.Substring($vaultPrefix.Length)
            $segments = $relative -split "[\\/]"
            -not ($segments | Where-Object { $_ -in @(".obsidian", ".trash", ".git") })
        } |
        Sort-Object FullName
}

function Get-RelativeNotePath([string]$FullName) {
    return $FullName.Substring($vaultPrefix.Length)
}

function Get-QueryTerms([string]$Text) {
    $termSet = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    $ignoredTerms = [System.Collections.Generic.HashSet[string]]::new(
        [System.StringComparer]::OrdinalIgnoreCase
    )
    @(
        "一般", "多少", "怎么", "什么", "看看", "文档", "帮我",
        "请问", "是否", "有没有"
    ) | ForEach-Object { [void]$ignoredTerms.Add($_) }

    $matches = [regex]::Matches(
        $Text,
        '[A-Za-z0-9][A-Za-z0-9._-]*|[\p{IsCJKUnifiedIdeographs}]+'
    )
    foreach ($match in $matches) {
        $value = $match.Value.Trim()
        if ($value.Length -lt 2) {
            continue
        }

        if ($value -match '^[A-Za-z0-9]') {
            [void]$termSet.Add($value)
            continue
        }

        if (-not $ignoredTerms.Contains($value)) {
            [void]$termSet.Add($value)
        }
        if ($value.Length -gt 2) {
            for ($index = 0; $index -le $value.Length - 2; $index++) {
                $bigram = $value.Substring($index, 2)
                if (-not $ignoredTerms.Contains($bigram)) {
                    [void]$termSet.Add($bigram)
                }
            }
        }
    }

    return @($termSet | Sort-Object)
}

function Test-SensitiveNote(
    [string]$FullName,
    [string]$RelativePath,
    [string]$Preview
) {
    $sensitivePattern = '(?i)(账密|密码|口令|凭证|密钥|私钥|token|secret|credential|password|passwd|api[\s_-]*key|bearer\s+\S+|root\s+\S+)'
    if ($RelativePath -match $sensitivePattern -or $Preview -match $sensitivePattern) {
        return $true
    }

    # Inspect frontmatter only. This classifies the note without treating its body
    # as retrieved evidence.
    $head = @(Get-Content -LiteralPath $FullName -Encoding UTF8 -TotalCount 80)
    if ($head.Count -eq 0 -or $head[0].Trim() -ne "---") {
        return $false
    }

    $frontmatterEnd = -1
    for ($index = 1; $index -lt $head.Count; $index++) {
        if ($head[$index].Trim() -eq "---") {
            $frontmatterEnd = $index
            break
        }
    }
    if ($frontmatterEnd -lt 1) {
        return $false
    }

    $frontmatter = ($head[1..($frontmatterEnd - 1)] -join "`n")
    return $frontmatter -match '(?im)^\s*sensitive\s*:\s*(true|yes|1)\s*(?:#.*)?$'
}

$graphModes = @(
    "links", "backlinks", "neighbors", "path", "cluster", "bridges",
    "hubs", "orphans", "relations", "stats", "unresolved",
    "suggest-links", "health", "report"
)

if ($Mode -in $graphModes) {
    $graphScript = Join-Path $PSScriptRoot "graph.ps1"
    & $graphScript `
        -Mode $Mode `
        -Note $Note `
        -From $From `
        -To $To `
        -Depth $Depth `
        -Top $Top `
        -Folder $Folder `
        -MaxResults $MaxResults `
        -MaxSuggestions $MaxSuggestions `
        -Backend $Backend
    exit $LASTEXITCODE
}

if ($Mode -eq "list") {
    $notes = Get-VaultNotes
    if (-not [string]::IsNullOrWhiteSpace($Query)) {
        $notes = $notes | Where-Object {
            (Get-RelativeNotePath $_.FullName).IndexOf(
                $Query,
                [System.StringComparison]::OrdinalIgnoreCase
            ) -ge 0
        }
    }

    $listedNotes = @(
        $notes |
            Select-Object -First $MaxResults |
            ForEach-Object {
                [pscustomobject]@{
                    path = Get-RelativeNotePath $_.FullName
                    title = $_.BaseName
                    modified = $_.LastWriteTime.ToString("o")
                    bytes = $_.Length
                }
            }
    )
    ConvertTo-Json -InputObject $listedNotes -Depth 4
    exit 0
}

if ($Mode -eq "read") {
    if ([string]::IsNullOrWhiteSpace($Note)) {
        throw "-Note is required when -Mode read is used."
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $vault $Note))
    if (
        -not $candidate.StartsWith($vaultPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetExtension($candidate) -ne ".md"
    ) {
        throw "The requested note must be a Markdown file inside the configured vault."
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Note not found: $Note"
    }

    Get-Content -LiteralPath $candidate -Raw -Encoding UTF8
    exit 0
}

if ($Mode -eq "read-json") {
    if ([string]::IsNullOrWhiteSpace($Note)) {
        throw "-Note is required when -Mode read-json is used."
    }

    $candidate = [System.IO.Path]::GetFullPath((Join-Path $vault $Note))
    if (
        -not $candidate.StartsWith($vaultPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetExtension($candidate) -ne ".md"
    ) {
        throw "The requested note must be a Markdown file inside the configured vault."
    }
    if (-not (Test-Path -LiteralPath $candidate -PathType Leaf)) {
        throw "Note not found: $Note"
    }

    $relative = Get-RelativeNotePath $candidate
    $isSensitive = Test-SensitiveNote `
        -FullName $candidate `
        -RelativePath $relative `
        -Preview ""
    if ($isSensitive -and -not $AllowSensitive) {
        throw "Sensitive note requires -AllowSensitive after an explicit user request: $Note"
    }

    [string]$content = Get-Content -LiteralPath $candidate -Raw -Encoding UTF8
    [string]$returnedContent = if ($content.Length -gt $MaxChars) {
        $content.Substring(0, $MaxChars)
    }
    else {
        [string]$content
    }
    $fileInfo = Get-Item -LiteralPath $candidate

    [pscustomobject]@{
        path = $relative
        modified = $fileInfo.LastWriteTime.ToString("o")
        sensitive = $isSensitive
        chars_total = $content.Length
        chars_returned = $returnedContent.Length
        truncated = $content.Length -gt $returnedContent.Length
        content = $returnedContent
    } | ConvertTo-Json -Depth 4
    exit 0
}

if ([string]::IsNullOrWhiteSpace($Query)) {
    throw "-Query is required when -Mode search is used."
}

# Synchronize only when the vault fingerprint changed. Re-running QMD update for
# an unchanged vault dominates query latency and makes the 3-second target
# unattainable. Count, newest write time, and total bytes also detect deletions
# and most content updates without storing note contents.
$syncStateRoot = Join-Path $skillRoot ".qmd"
$syncStatePath = Join-Path $syncStateRoot "vault-sync-state.json"
$vaultNotes = @(Get-VaultNotes)
$newestWriteTicks = 0L
$totalBytes = 0L
foreach ($vaultNote in $vaultNotes) {
    $totalBytes += [long]$vaultNote.Length
    if ($vaultNote.LastWriteTimeUtc.Ticks -gt $newestWriteTicks) {
        $newestWriteTicks = $vaultNote.LastWriteTimeUtc.Ticks
    }
}
$vaultFingerprint = [ordered]@{
    note_count = $vaultNotes.Count
    newest_write_ticks = $newestWriteTicks
    total_bytes = $totalBytes
}

$needsSync = $true
if (Test-Path -LiteralPath $syncStatePath -PathType Leaf) {
    try {
        $syncState = Get-Content -LiteralPath $syncStatePath -Raw -Encoding UTF8 |
            ConvertFrom-Json
        $needsSync = (
            [int]$syncState.note_count -ne $vaultFingerprint.note_count -or
            [long]$syncState.newest_write_ticks -ne $vaultFingerprint.newest_write_ticks -or
            [long]$syncState.total_bytes -ne $vaultFingerprint.total_bytes
        )
    }
    catch {
        $needsSync = $true
    }
}

if ($needsSync) {
    # QMD prints update progress to stderr, so suppress both streams here.
    & $qmdExecutable $qmdEntry update *> $null
    if ($LASTEXITCODE -ne 0) {
        throw "QMD failed to update collection '$qmdCollection'."
    }

    New-Item -ItemType Directory -Path $syncStateRoot -Force | Out-Null
    $vaultFingerprint | ConvertTo-Json |
        Set-Content -LiteralPath $syncStatePath -Encoding UTF8
}

$candidateLimit = [Math]::Min(500, [Math]::Max($MaxResults * 3, 20))
$qmdJson = & $qmdExecutable $qmdEntry search $Query `
    -c $qmdCollection `
    -n $candidateLimit `
    --format json `
    --full-path `
    --line-numbers
if ($LASTEXITCODE -ne 0) {
    throw "QMD search failed for collection '$qmdCollection'."
}

$qmdResults = @()
if (-not [string]::IsNullOrWhiteSpace(($qmdJson -join "`n"))) {
    $qmdResults = ($qmdJson -join "`n") | ConvertFrom-Json
}

$results = [System.Collections.Generic.List[object]]::new()
$seenPaths = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase
)

foreach ($result in $qmdResults) {
    if ($results.Count -ge $MaxResults) {
        break
    }

    $fullName = [System.IO.Path]::GetFullPath([string]$result.file)
    if (
        -not $fullName.StartsWith($vaultPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetExtension($fullName) -ne ".md"
    ) {
        continue
    }

    $relative = Get-RelativeNotePath $fullName
    if (-not $seenPaths.Add($relative)) {
        continue
    }
    $preview = [string]$result.snippet
    $isSensitive = Test-SensitiveNote `
        -FullName $fullName `
        -RelativePath $relative `
        -Preview $preview
    if ($isSensitive) {
        $preview = "[redacted: potentially sensitive match]"
    }
    $fileInfo = Get-Item -LiteralPath $fullName

    $results.Add([pscustomobject]@{
        path = $relative
        title = [string]$result.title
        modified = $fileInfo.LastWriteTime.ToString("o")
        line = if ($null -eq $result.line) { $null } else { [int]$result.line }
        preview = $preview
        match = "qmd_bm25"
        score = [double]$result.score
        sensitive = $isSensitive
    })
}

# QMD BM25 treats verbose multi-keyword queries narrowly, which is especially
# brittle for short Chinese notes. Preserve QMD ranking, then fill remaining
# slots with deterministic title/path token matches.
if ($results.Count -lt $MaxResults) {
    $queryTerms = @(Get-QueryTerms $Query)
    if ($queryTerms.Count -gt 0) {
        $titleMatches = @(
            foreach ($vaultNote in $vaultNotes) {
                $relative = Get-RelativeNotePath $vaultNote.FullName
                if ($seenPaths.Contains($relative)) {
                    continue
                }

                $searchText = "$relative $($vaultNote.BaseName)"
                $matchedTerms = @(
                    $queryTerms | Where-Object {
                        $searchText.IndexOf(
                            $_,
                            [System.StringComparison]::OrdinalIgnoreCase
                        ) -ge 0
                    }
                )
                if ($matchedTerms.Count -eq 0) {
                    continue
                }

                [pscustomobject]@{
                    file = $vaultNote
                    relative = $relative
                    matched_count = $matchedTerms.Count
                    score = [double]$matchedTerms.Count / [double]$queryTerms.Count
                }
            }
        ) | Sort-Object `
            @{ Expression = "matched_count"; Descending = $true }, `
            @{ Expression = "score"; Descending = $true }, `
            @{ Expression = "relative"; Descending = $false }

        foreach ($titleMatch in $titleMatches) {
            if ($results.Count -ge $MaxResults) {
                break
            }
            if (-not $seenPaths.Add([string]$titleMatch.relative)) {
                continue
            }

            $isSensitive = Test-SensitiveNote `
                -FullName $titleMatch.file.FullName `
                -RelativePath $titleMatch.relative `
                -Preview ""
            $results.Add([pscustomobject]@{
                path = $titleMatch.relative
                title = $titleMatch.file.BaseName
                modified = $titleMatch.file.LastWriteTime.ToString("o")
                line = $null
                preview = if ($isSensitive) {
                    "[redacted: potentially sensitive title match]"
                }
                else {
                    "[matched by note title/path]"
                }
                match = "title_tokens"
                score = [double]$titleMatch.score
                sensitive = $isSensitive
            })
        }
    }
}

ConvertTo-Json -InputObject @($results) -Depth 4
