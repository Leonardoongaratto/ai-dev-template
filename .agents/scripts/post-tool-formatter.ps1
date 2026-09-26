$ErrorActionPreference = 'Stop'

function Test-IsWindowsPlatform {
    $v = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
    if ($null -ne $v) { return [bool]$v.Value }
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Test-IsMacPlatform {
    $v = Get-Variable -Name 'IsMacOS' -ErrorAction SilentlyContinue
    if ($null -ne $v) { return [bool]$v.Value }
    return $false
}

function Join-Segments([string]$base, [string[]]$segments) {
    $result = $base
    foreach ($segment in $segments) { $result = Join-Path $result $segment }
    return $result
}

$OnWindows = Test-IsWindowsPlatform
$PathComparisonType = [StringComparison]::Ordinal
if ($OnWindows -or (Test-IsMacPlatform)) { $PathComparisonType = [StringComparison]::OrdinalIgnoreCase }
$Separator = [IO.Path]::DirectorySeparatorChar
$PrettierRelativeSegments = @('node_modules', '.bin', 'prettier')
if ($OnWindows) { $PrettierRelativeSegments = @('node_modules', '.bin', 'prettier.cmd') }

$FormattableExtensions = @('.ts', '.tsx', '.js', '.jsx', '.css', '.json')
$WorkspaceRoot = [IO.Path]::GetFullPath((Join-Segments $PSScriptRoot @('..', '..'))).TrimEnd($Separator)

function Read-HookPayload {
    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Get-EditedFilePath($payload) {
    if ($payload.tool_input -and $payload.tool_input.file_path) { return [string]$payload.tool_input.file_path }
    if ($payload.toolCall -and $payload.toolCall.args -and $payload.toolCall.args.TargetFile) { return [string]$payload.toolCall.args.TargetFile }
    return $null
}

function Test-PathEquals([string]$a, [string]$b) {
    return [string]::Equals($a, $b, $PathComparisonType)
}

function Test-InsideWorkspace([string]$path) {
    return $path.StartsWith($WorkspaceRoot + $Separator, $PathComparisonType)
}

function Find-LocalPrettier([string]$filePath) {
    $directory = Split-Path -Parent $filePath
    while ($directory -and (Test-InsideWorkspace ($directory + $Separator))) {
        $candidate = Join-Segments $directory $PrettierRelativeSegments
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        if (Test-PathEquals $directory $WorkspaceRoot) { break }
        $parent = Split-Path -Parent $directory
        if ($parent -eq $directory) { break }
        $directory = $parent
    }
    return $null
}

function Invoke-Formatter([string]$rawInput) {
    if (-not $rawInput) { return 'skip: empty input' }
    $payload = $rawInput | ConvertFrom-Json
    $editedPath = Get-EditedFilePath $payload
    if (-not $editedPath) { return 'skip: no file path in payload' }

    $fullPath = [IO.Path]::GetFullPath($editedPath)
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { return 'skip: file not found' }
    if ($FormattableExtensions -notcontains [IO.Path]::GetExtension($fullPath).ToLowerInvariant()) { return 'skip: extension not formatted' }
    if (-not (Test-InsideWorkspace $fullPath)) { return 'skip: outside workspace' }

    $prettier = Find-LocalPrettier $fullPath
    if (-not $prettier) { return 'skip: no local prettier' }

    $ErrorActionPreference = 'Continue'
    & $prettier --write --log-level=silent $fullPath 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { return "skip: prettier exit $LASTEXITCODE (node missing from PATH?): $fullPath" }
    return "formatted: $fullPath"
}

try {
    $result = Invoke-Formatter (Read-HookPayload)
} catch {
    $result = 'skip: error ' + $_.Exception.Message
}

if ($env:POST_TOOL_FORMATTER_DEBUG -eq '1') { [Console]::Error.WriteLine($result) }
Write-Output '{}'
exit 0
