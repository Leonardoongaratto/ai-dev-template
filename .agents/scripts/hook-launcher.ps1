$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$FormatterRelativeSegments = @('.agents', 'scripts', 'post-tool-formatter.ps1')

function Join-Segments([string]$base, [string[]]$segments) {
    $result = $base
    foreach ($segment in $segments) { $result = Join-Path $result $segment }
    return $result
}

function Get-FormatterIn([string]$directory) {
    if (-not $directory) { return $null }
    try { $candidate = Join-Segments $directory $FormatterRelativeSegments } catch { return $null }
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    return $null
}

function Find-Formatter {
    $fromProject = Get-FormatterIn $env:CLAUDE_PROJECT_DIR
    if ($fromProject) { return $fromProject }
    $directory = (Get-Location).ProviderPath
    while ($directory) {
        $found = Get-FormatterIn $directory
        if ($found) { return $found }
        $parent = Split-Path -Parent $directory
        if ($parent -eq $directory) { break }
        $directory = $parent
    }
    return $null
}

$formatter = Find-Formatter
if (-not $formatter) {
    if ($env:POST_TOOL_FORMATTER_DEBUG -eq '1') { [Console]::Error.WriteLine('skip: formatter script not found') }
    Write-Output '{}'
    exit 0
}
try {
    & $formatter *> $null
} catch {
    if ($env:POST_TOOL_FORMATTER_DEBUG -eq '1') { [Console]::Error.WriteLine('skip: formatter error ' + $_.Exception.Message) }
}
Write-Output '{}'
exit 0
