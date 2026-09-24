$ErrorActionPreference = 'Stop'

$FormattableExtensions = @('.ts', '.tsx', '.js', '.jsx', '.css', '.json')
$WorkspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')).TrimEnd('\')

function Read-HookPayload {
    $reader = New-Object IO.StreamReader([Console]::OpenStandardInput(), [Text.Encoding]::UTF8)
    try { return $reader.ReadToEnd() } finally { $reader.Dispose() }
}

function Get-EditedFilePath($payload) {
    if ($payload.tool_input -and $payload.tool_input.file_path) { return [string]$payload.tool_input.file_path }
    if ($payload.toolCall -and $payload.toolCall.args -and $payload.toolCall.args.TargetFile) { return [string]$payload.toolCall.args.TargetFile }
    return $null
}

function Test-InsideWorkspace([string]$path) {
    return $path.StartsWith($WorkspaceRoot + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Find-LocalPrettier([string]$filePath) {
    $directory = Split-Path -Parent $filePath
    while ($directory -and (Test-InsideWorkspace ($directory + '\'))) {
        $candidate = Join-Path $directory 'node_modules\.bin\prettier.cmd'
        if (Test-Path -LiteralPath $candidate) { return $candidate }
        if ($directory -ieq $WorkspaceRoot) { break }
        $directory = Split-Path -Parent $directory
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
