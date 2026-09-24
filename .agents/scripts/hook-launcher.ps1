$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
$FormatterRelativePath = '.agents\scripts\post-tool-formatter.ps1'

function Get-FormatterIn([string]$directory) {
    if (-not $directory) { return $null }
    try { $candidate = Join-Path $directory $FormatterRelativePath } catch { return $null }
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
        $directory = Split-Path -Parent $directory
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
