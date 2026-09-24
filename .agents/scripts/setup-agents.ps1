param([switch]$PrintHookCommand, [switch]$SkipGraphifyInstall)

$ErrorActionPreference = 'Stop'

$workspaceRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$skillsTarget = Join-Path $workspaceRoot '.agents\skills'
$claudeDir = Join-Path $workspaceRoot '.claude'
$skillsLink = Join-Path $claudeDir 'skills'
$hookLauncher = Join-Path $workspaceRoot '.agents\scripts\hook-launcher.ps1'
$hookConfigs = @(
    (Join-Path $workspaceRoot '.claude\settings.json'),
    (Join-Path $workspaceRoot '.agents\hooks.json')
)
$hookCommandPattern = '("command"\s*:\s*")powershell [^"]*?(?:post-tool-formatter\.ps1|-EncodedCommand [A-Za-z0-9+/=]+)(")'

function Get-JunctionTarget([string]$path) {
    $item = Get-Item -LiteralPath $path -Force
    if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) { return $null }
    return [string]@($item.Target)[0]
}

function Get-HookCommand {
    $source = [IO.File]::ReadAllText($hookLauncher) -replace "`r`n", "`n"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($source))
    return 'powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand ' + $encoded
}

function Sync-SkillsJunction {
    if (-not (Test-Path -LiteralPath $skillsTarget)) { throw "Skills source not found: $skillsTarget" }
    if (-not (Test-Path -LiteralPath $claudeDir)) { New-Item -ItemType Directory -Path $claudeDir | Out-Null }

    if (Test-Path -LiteralPath $skillsLink) {
        $currentTarget = Get-JunctionTarget $skillsLink
        if ($null -eq $currentTarget) {
            throw "$skillsLink is a real directory, not a junction. Move its contents to .agents\skills and delete it, then run this script again."
        }
        if ($currentTarget.TrimEnd('\') -ieq $skillsTarget.TrimEnd('\')) { return 'OK: .claude\skills already points to .agents\skills' }
        cmd /c rmdir "$skillsLink" | Out-Null
    }

    cmd /c mklink /J "$skillsLink" "$skillsTarget" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "mklink /J failed with exit code $LASTEXITCODE" }
    return 'CREATED: .claude\skills -> .agents\skills'
}

function Get-JsonErrorSummary([string]$message) {
    $firstLine = ($message -split "`r?`n")[0]
    $inputEcho = $firstLine.IndexOf('): ')
    if ($inputEcho -ge 0) { return $firstLine.Substring(0, $inputEcho + 1) }
    if ($firstLine.Length -gt 200) { return $firstLine.Substring(0, 200) + '...' }
    return $firstLine
}

function Get-HookConfigUpdate([string]$configPath, [string]$command) {
    $name = $configPath.Substring($workspaceRoot.Length).TrimStart('\')
    $current = [IO.File]::ReadAllText($configPath)
    $matchCount = ([regex]::Matches($current, $hookCommandPattern)).Count
    if ($matchCount -ne 1) { throw "$name must contain exactly one post-tool-formatter hook command, found $matchCount" }
    $updated = [regex]::Replace($current, $hookCommandPattern, { param($m) $m.Groups[1].Value + $command + $m.Groups[2].Value })
    try { $null = $updated | ConvertFrom-Json }
    catch { throw "$configPath is not valid JSON: $(Get-JsonErrorSummary $_.Exception.Message)" }
    return [pscustomobject]@{ Path = $configPath; Name = $name; Original = $current; Content = $updated; Changed = -not ($updated -ceq $current) }
}

function Sync-HookCommands([string[]]$configPaths, [string]$command) {
    $utf8 = New-Object Text.UTF8Encoding($false)
    $updates = @(foreach ($configPath in $configPaths) { Get-HookConfigUpdate $configPath $command })
    $written = New-Object System.Collections.Generic.List[object]
    try {
        foreach ($update in @($updates | Where-Object { $_.Changed })) {
            [IO.File]::WriteAllText($update.Path, $update.Content, $utf8)
            $written.Add($update)
        }
    } catch {
        foreach ($update in $written) { [IO.File]::WriteAllText($update.Path, $update.Original, $utf8) }
        throw
    }
    foreach ($update in $updates) {
        if ($update.Changed) { Write-Output "UPDATED: $($update.Name) hook command regenerated from hook-launcher.ps1" }
        else { Write-Output "OK: $($update.Name) hook command is up to date" }
    }
}

function Get-GraphifyGlobalPaths {
    $claudeRoot = if ($env:CLAUDE_CONFIG_DIR) { $env:CLAUDE_CONFIG_DIR } else { Join-Path $env:USERPROFILE '.claude' }
    return [ordered]@{
        claude = @((Join-Path $claudeRoot 'skills\graphify\'), (Join-Path $claudeRoot 'CLAUDE.md'))
        antigravity = @(Join-Path $env:USERPROFILE '.gemini\config\skills\graphify\')
    }
}

function Invoke-GraphifyInstall([string]$platform) {
    $ErrorActionPreference = 'Continue'
    & graphify install --platform $platform *> $null
    return $LASTEXITCODE
}

function Install-GraphifySkill {
    if ($SkipGraphifyInstall) {
        Write-Output 'SKIP: graphify install (-SkipGraphifyInstall)'
        return
    }
    $graphify = Get-Command graphify -ErrorAction SilentlyContinue
    if (-not $graphify) {
        Write-Output 'WARN: graphify not found on PATH. Install with: python -m pip install "graphifyy[mcp]"'
        return
    }
    $globalPaths = Get-GraphifyGlobalPaths
    foreach ($platform in $globalPaths.Keys) {
        $exitCode = Invoke-GraphifyInstall $platform
        if ($exitCode -eq 0) { Write-Output "OK: graphify install --platform $platform" }
        else { Write-Output "WARN: graphify install --platform $platform exited with code $exitCode" }
        foreach ($path in $globalPaths[$platform]) { Write-Output "GLOBAL: $path" }
    }
}

try {
    $hookCommand = Get-HookCommand
    if ($PrintHookCommand) {
        Write-Output $hookCommand
        exit 0
    }
    Write-Output (Sync-SkillsJunction)
    Sync-HookCommands $hookConfigs $hookCommand
    Install-GraphifySkill
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
exit 0
