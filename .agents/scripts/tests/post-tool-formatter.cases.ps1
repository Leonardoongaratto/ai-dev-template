$ErrorActionPreference = 'Stop'

$WorkspaceRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\..')).TrimEnd('\')
$Subproject = Join-Path $PSScriptRoot ('.fixture-' + [guid]::NewGuid().ToString('N'))
$FixtureDir = Join-Path $Subproject 'src'
$Prettier = Join-Path $Subproject 'node_modules\.bin\prettier.cmd'
$SetupScript = Join-Path $WorkspaceRoot '.agents\scripts\setup-agents.ps1'
$HookLauncher = Join-Path $WorkspaceRoot '.agents\scripts\hook-launcher.ps1'
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$MinimalPath = Join-Path $env:SystemRoot 'System32'
$SentinelBin = Join-Path $Subproject 'inherited-path-bin'
$SentinelLog = Join-Path $Subproject 'inherited-graphify-calls.log'
$InheritedPath = $env:PATH
$UnformattedSource = "const  hookCase={alpha:1,beta:'two'}`nexport default   hookCase`n"
$ShimMarker = '// formatted by fixture prettier shim'
$ShimExpected = $ShimMarker + "`r`n" + $UnformattedSource
$PrettierShim = @'
@echo off
setlocal
set "write="
set "target="
:next
if "%~1"=="" goto run
if "%~1"=="--write" set "write=1"
set "target=%~1"
shift
goto next
:run
if not defined write exit /b 2
if not exist "%target%" exit /b 3
> "%target%.shim" (
  echo // formatted by fixture prettier shim
  type "%target%"
)
move /y "%target%.shim" "%target%" > nul
'@
$MarkdownSource = "#   Title   `n`n*  item`n"
$BrokenFormatters = [ordered]@{
    'syntax error' = "if (`n"
    'throw' = "throw 'broken formatter'`n"
    'Write-Error' = "Write-Error 'broken formatter'`n"
    'native stderr' = "cmd /c `"echo broken formatter 1>&2`"`nWrite-Output 'noise'`n"
}
$Results = New-Object System.Collections.Generic.List[object]
$CreatedFiles = New-Object System.Collections.Generic.List[string]
$TempDirectories = New-Object System.Collections.Generic.List[string]

function New-SubprojectFixture {
    New-Item -ItemType Directory -Path $FixtureDir, (Split-Path -Parent $Prettier) -Force | Out-Null
    [IO.File]::WriteAllText($Prettier, ($PrettierShim -replace "`r?`n", "`r`n"), (New-Object Text.ASCIIEncoding))
}

function Find-PosixShell {
    $onPath = Get-Command sh -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\usr\bin\sh.exe'),
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'),
        (Join-Path $env:ProgramFiles 'Git\usr\bin\sh.exe'),
        (Join-Path $env:ProgramFiles 'Git\bin\bash.exe')
    )
    foreach ($candidate in $candidates) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-HookCommand([string]$configPath, [string]$section) {
    $config = Get-Content -LiteralPath $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
    return [string]$config.$section.PostToolUse[0].hooks[0].command
}

function New-Fixture([string]$name, [string]$content) {
    $path = Join-Path $FixtureDir $name
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
    $CreatedFiles.Add($path)
    return $path
}

function Get-ExpectedFormatted {
    $reference = New-Fixture '__hook_case_reference.ts' $UnformattedSource
    & $Prettier --write --log-level=silent $reference | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "prettier shim failed on reference fixture: exit $LASTEXITCODE" }
    $formatted = [IO.File]::ReadAllText($reference)
    Add-Result 'fixture prettier shim rewrites file' ($formatted -ceq $ShimExpected) ("matches marker+source={0}" -f ($formatted -ceq $ShimExpected))
    return $ShimExpected
}

function Get-ShellInvocation([string]$shell, [string]$command) {
    switch ($shell) {
        'cmd' { return @{ File = $env:ComSpec; Arguments = "/d /c $command" } }
        'sh' { return @{ File = $PosixShell; Arguments = "-c `"$command`"" } }
        'powershell' { return @{ File = 'powershell.exe'; Arguments = "-NoProfile -NonInteractive -Command $command" } }
    }
    throw "unknown shell: $shell"
}

function Invoke-Hook([string]$shell, [string]$command, [string]$workingDirectory, [string]$stdin, [string]$projectDir) {
    $invocation = Get-ShellInvocation $shell $command
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $invocation.File
    $info.Arguments = $invocation.Arguments
    $info.WorkingDirectory = $workingDirectory
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    if ($projectDir) { $info.EnvironmentVariables['CLAUDE_PROJECT_DIR'] = $projectDir }
    else { $info.EnvironmentVariables.Remove('CLAUDE_PROJECT_DIR') }
    $process = [Diagnostics.Process]::Start($info)
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($stdin)
    $process.StandardInput.Close()
    $stdout = $process.StandardOutput.ReadToEnd()
    if (-not $process.WaitForExit(60000)) { $process.Kill(); return @{ ExitCode = 'timeout'; Stdout = $stdout; Stderr = '' } }
    return @{ ExitCode = $process.ExitCode; Stdout = $stdout.Trim(); Stderr = $stderrTask.Result.Trim() }
}

function Add-Result([string]$name, [bool]$passed, [string]$detail) {
    $compact = ($detail -replace '\s+', ' ').Trim()
    if ($compact.Length -gt 160) { $compact = $compact.Substring(0, 160) + '...' }
    $Results.Add([pscustomobject]@{ Case = $name; Result = $(if ($passed) { 'PASS' } else { 'FAIL' }); Detail = $compact })
}

function Test-FormatCase([string]$name, [string]$shell, [string]$command, [string]$workingDirectory, [string]$format, [string]$projectDir) {
    $fixture = New-Fixture ("__hook_case_{0}.ts" -f ($name -replace '[^A-Za-z0-9]', '_')) $UnformattedSource
    $escaped = $fixture.Replace('\', '\\')
    if ($format -eq 'claude') { $payload = '{"hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"' + $escaped + '"}}' }
    else { $payload = '{"toolCall":{"name":"write_to_file","args":{"TargetFile":"' + $escaped + '"}}}' }
    $run = Invoke-Hook $shell $command $workingDirectory $payload $projectDir
    $content = [IO.File]::ReadAllText($fixture)
    $passed = ($run.ExitCode -eq 0) -and ($run.Stdout -eq '{}') -and ($run.Stderr -eq '') -and ($content -ceq $ExpectedFormatted)
    Add-Result $name $passed ("exit={0} stdout={1} formatted={2} stderr={3}" -f $run.ExitCode, $run.Stdout, ($content -ceq $ExpectedFormatted), $run.Stderr)
}

function Test-NoOpCase([string]$name, [string]$command, [string]$stdin, [string]$fixture, [string]$originalContent, [string]$workingDirectory = $Subproject, [string]$projectDir = $WorkspaceRoot) {
    $run = Invoke-Hook 'powershell' $command $workingDirectory $stdin $projectDir
    $untouched = $true
    if ($fixture) { $untouched = ([IO.File]::ReadAllText($fixture) -ceq $originalContent) }
    $passed = ($run.ExitCode -eq 0) -and ($run.Stdout -ceq '{}') -and ($run.Stderr -eq '') -and $untouched
    Add-Result $name $passed ("exit={0} stdout={1} untouched={2} stderr={3}" -f $run.ExitCode, $run.Stdout, $untouched, $run.Stderr)
}

function Test-CommandInSync([string]$name, [string]$actual, [string]$expected) {
    Add-Result $name ($actual -ceq $expected) ("length actual={0} expected={1}" -f $actual.Length, $expected.Length)
}

function New-TempWorkspace {
    $root = Join-Path ([IO.Path]::GetTempPath()) ('hook-case-' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path (Join-Path $root '.agents\scripts') -Force | Out-Null
    $TempDirectories.Add($root)
    return $root
}

function Write-AsciiFile([string]$path, [string]$content) {
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
}

function Get-PrintedHookCommand([string]$setupScript) {
    return (& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $setupScript -PrintHookCommand | Out-String).Trim()
}

function Test-LineEndingIndependence([string]$expected) {
    $normalized = [IO.File]::ReadAllText($HookLauncher) -replace "`r`n", "`n"
    $variants = [ordered]@{ LF = $normalized; CRLF = $normalized -replace "`n", "`r`n" }
    foreach ($variant in $variants.GetEnumerator()) {
        $scripts = Join-Path (New-TempWorkspace) '.agents\scripts'
        Copy-Item -LiteralPath $SetupScript -Destination $scripts
        Write-AsciiFile (Join-Path $scripts 'hook-launcher.ps1') $variant.Value
        $actual = Get-PrintedHookCommand (Join-Path $scripts 'setup-agents.ps1')
        Test-CommandInSync "$($variant.Key) launcher copy generates committed command" $actual $expected
    }
}

function Invoke-SetupIn([string]$workspace) {
    return Invoke-SetupWithPath $workspace $MinimalPath
}

function Test-AtomicHookUpdate([string]$expected) {
    $workspace = New-TempWorkspace
    $scripts = Join-Path $workspace '.agents\scripts'
    Copy-Item -LiteralPath $SetupScript, $HookLauncher -Destination $scripts
    New-Item -ItemType Directory -Path (Join-Path $workspace '.agents\skills'), (Join-Path $workspace '.claude') -Force | Out-Null
    $settings = Join-Path $workspace '.claude\settings.json'
    $hooks = Join-Path $workspace '.agents\hooks.json'
    $staleHook = '{"type":"command","command":"powershell -NoProfile -File .agents/scripts/post-tool-formatter.ps1"}'
    $settingsSource = '{"hooks":{"PostToolUse":[{"matcher":"Edit|Write","hooks":[' + $staleHook + ']}]}}'
    Write-AsciiFile $settings $settingsSource
    Write-AsciiFile $hooks '{"code-formatter":{"PostToolUse":[]}}'

    $run = Invoke-SetupIn $workspace
    $untouched = [IO.File]::ReadAllText($settings) -ceq $settingsSource
    Add-Result 'setup invalid hooks.json writes neither file' (($run.ExitCode -eq 1) -and $untouched) ("exit={0} settings.json untouched={1}" -f $run.ExitCode, $untouched)

    $hooksSource = '{"code-formatter":{"PostToolUse":[{"hooks":[' + $staleHook + ']}]}}'
    Write-AsciiFile $hooks $hooksSource.Substring(0, $hooksSource.Length - 1)
    $run = Invoke-SetupIn $workspace
    $untouched = [IO.File]::ReadAllText($settings) -ceq $settingsSource
    $short = ($run.Stderr -notmatch "`n") -and $run.Stderr.Contains($hooks) -and (-not $run.Stderr.Contains('EncodedCommand')) -and ($run.Stderr.Length -le 400)
    Add-Result 'setup malformed hooks.json short error' (($run.ExitCode -eq 1) -and $untouched -and $short) ("exit={0} untouched={1} short={2} stderr length={3}" -f $run.ExitCode, $untouched, $short, $run.Stderr.Length)

    Write-AsciiFile $hooks $hooksSource
    (Get-Item -LiteralPath $hooks).IsReadOnly = $true
    try {
        $run = Invoke-SetupIn $workspace
        $restored = [IO.File]::ReadAllText($settings) -ceq $settingsSource
        Add-Result 'setup write failure restores written file' (($run.ExitCode -eq 1) -and $restored) ("exit={0} settings.json restored={1}" -f $run.ExitCode, $restored)
    }
    finally {
        (Get-Item -LiteralPath $hooks).IsReadOnly = $false
    }

    $run = Invoke-SetupIn $workspace
    $synced = @($settings, $hooks | Where-Object { [IO.File]::ReadAllText($_).Contains('"command":"' + $expected + '"') }).Count
    Add-Result 'setup valid configs updates both files' (($run.ExitCode -eq 0) -and ($synced -eq 2)) ("exit={0} files synced={1}" -f $run.ExitCode, $synced)
}

function Test-BrokenFormatterCase([string]$mode, [string]$source, [string]$command) {
    $workspace = New-TempWorkspace
    Write-AsciiFile (Join-Path $workspace '.agents\scripts\post-tool-formatter.ps1') $source
    $fixture = New-Fixture ("__hook_case_broken_{0}.ts" -f ($mode -replace '[^A-Za-z0-9]', '_')) $UnformattedSource
    $payload = '{"tool_input":{"file_path":"' + $fixture.Replace('\', '\\') + '"}}'
    Test-NoOpCase "broken formatter: $mode" $command $payload $fixture $UnformattedSource $env:SystemRoot $workspace
}

function New-GraphifyTestWorkspace {
    $workspace = New-TempWorkspace
    $scripts = Join-Path $workspace '.agents\scripts'
    Copy-Item -LiteralPath $SetupScript, $HookLauncher -Destination $scripts
    New-Item -ItemType Directory -Path (Join-Path $workspace '.agents\skills'), (Join-Path $workspace '.claude') -Force | Out-Null
    $settings = Join-Path $workspace '.claude\settings.json'
    $hooks = Join-Path $workspace '.agents\hooks.json'
    $staleHook = '{"type":"command","command":"powershell -NoProfile -File .agents/scripts/post-tool-formatter.ps1"}'
    Write-AsciiFile $settings ('{"hooks":{"PostToolUse":[{"matcher":"Edit|Write","hooks":[' + $staleHook + ']}]}}')
    Write-AsciiFile $hooks ('{"code-formatter":{"PostToolUse":[{"hooks":[' + $staleHook + ']}]}}')
    return $workspace
}

function New-GraphifyShim([string]$binDir, [string]$logPath, [string]$extraLines = '', [int]$exitCode = 0) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    $shim = "@echo off`r`n>> `"$logPath`" echo %*`r`n$extraLines" + "exit /b $exitCode`r`n"
    [IO.File]::WriteAllText((Join-Path $binDir 'graphify.cmd'), $shim, (New-Object Text.ASCIIEncoding))
}

function Get-LogLines([string]$logPath) {
    if (-not (Test-Path -LiteralPath $logPath)) { return @() }
    return @(Get-Content -LiteralPath $logPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-MatchCount([string]$text, [string]$literal) {
    return ([regex]::Matches($text, [regex]::Escape($literal))).Count
}

function Invoke-SetupWithPath([string]$workspace, [string]$pathValue, [string]$extraArguments = '', [hashtable]$environment = @{}) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $PowerShellExe
    $info.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" {1}' -f (Join-Path $workspace '.agents\scripts\setup-agents.ps1'), $extraArguments).Trim()
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $info.EnvironmentVariables['PATH'] = $pathValue
    $info.EnvironmentVariables.Remove('CLAUDE_CONFIG_DIR')
    foreach ($entry in $environment.GetEnumerator()) { $info.EnvironmentVariables[$entry.Key] = $entry.Value }
    $process = [Diagnostics.Process]::Start($info)
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.WaitForExit()
    return @{ ExitCode = $process.ExitCode; Stdout = $stdoutTask.Result; Stderr = $stderrTask.Result.Trim() }
}

function Test-GraphifyAbsentCase {
    $workspace = New-GraphifyTestWorkspace
    $run = Invoke-SetupWithPath $workspace $MinimalPath
    $warned = $run.Stdout -match 'graphify not found on PATH'
    Add-Result 'setup warns when graphify missing from PATH' (($run.ExitCode -eq 0) -and $warned) ("exit={0} warned={1}" -f $run.ExitCode, $warned)
}

function Get-PlatformCallCounts([string[]]$lines) {
    return @{
        claude = @($lines | Where-Object { $_ -ceq 'install --platform claude' }).Count
        antigravity = @($lines | Where-Object { $_ -ceq 'install --platform antigravity' }).Count
    }
}

function Test-GraphifyPresentCase {
    $workspace = New-GraphifyTestWorkspace
    $binDir = Join-Path $workspace 'bin'
    $logPath = Join-Path $workspace 'graphify-calls.log'
    New-GraphifyShim $binDir $logPath
    $pathValue = $binDir + ';' + $MinimalPath
    $run = Invoke-SetupWithPath $workspace $pathValue
    $first = @(Get-LogLines $logPath)
    $counts = Get-PlatformCallCounts $first
    $once = ($first.Count -eq 2) -and ($counts.claude -eq 1) -and ($counts.antigravity -eq 1)
    $okLines = $run.Stdout.Contains('OK: graphify install --platform claude') -and $run.Stdout.Contains('OK: graphify install --platform antigravity')
    Add-Result 'setup installs graphify skill for claude and antigravity when present' (($run.ExitCode -eq 0) -and $once -and $okLines) ("exit={0} calls={1} claude={2} antigravity={3} ok={4}" -f $run.ExitCode, $first.Count, $counts.claude, $counts.antigravity, $okLines)

    $run2 = Invoke-SetupWithPath $workspace $pathValue
    $all = @(Get-LogLines $logPath)
    $second = @($all | Select-Object -Skip $first.Count)
    $counts2 = Get-PlatformCallCounts $second
    $onceAgain = ($all.Count -eq 4) -and ($second.Count -eq 2) -and ($counts2.claude -eq 1) -and ($counts2.antigravity -eq 1)
    $junctionOk = $run2.Stdout.Contains('OK: .claude\skills already points to .agents\skills')
    $hooksOk = (Get-MatchCount $run2.Stdout 'hook command is up to date') -eq 2
    $passed = ($run2.ExitCode -eq 0) -and $onceAgain -and $junctionOk -and $hooksOk
    Add-Result 'setup graphify step is idempotent on second run' $passed ("exit={0} total calls={1} second run calls={2} junction ok={3} hooks up to date={4}" -f $run2.ExitCode, $all.Count, $second.Count, $junctionOk, $hooksOk)
}

function Test-GraphifyFailureCase([string]$name, [string]$extraLines, [int]$exitCode, [string[]]$expectedLines) {
    $workspace = New-GraphifyTestWorkspace
    $binDir = Join-Path $workspace 'bin'
    $logPath = Join-Path $workspace 'graphify-calls.log'
    New-GraphifyShim $binDir $logPath $extraLines $exitCode
    $run = Invoke-SetupWithPath $workspace ($binDir + ';' + $MinimalPath)
    $missing = @($expectedLines | Where-Object { -not $run.Stdout.Contains($_) })
    $calls = @(Get-LogLines $logPath).Count
    $passed = ($run.ExitCode -eq 0) -and ($missing.Count -eq 0) -and ($calls -eq 2)
    Add-Result $name $passed ("exit={0} calls={1} missing={2} stderr={3}" -f $run.ExitCode, $calls, ($missing -join ' / '), $run.Stderr)
}

function Test-GraphifyFailureCases {
    Test-GraphifyFailureCase 'setup survives graphify stderr with exit 0' "echo graphify warning 1>&2`r`n" 0 @('OK: graphify install --platform claude', 'OK: graphify install --platform antigravity')
    Test-GraphifyFailureCase 'setup warns and exits 0 when graphify exits 3' "echo graphify failure 1>&2`r`n" 3 @('WARN: graphify install --platform claude exited with code 3', 'WARN: graphify install --platform antigravity exited with code 3')
}

function Test-GraphifyGlobalPathsCase {
    $workspace = New-GraphifyTestWorkspace
    $binDir = Join-Path $workspace 'bin'
    $logPath = Join-Path $workspace 'graphify-calls.log'
    New-GraphifyShim $binDir $logPath
    $fakeHome = Join-Path $workspace 'home'
    $pathValue = $binDir + ';' + $MinimalPath
    $run = Invoke-SetupWithPath $workspace $pathValue '' @{ USERPROFILE = $fakeHome }
    $expected = @(
        ('GLOBAL: ' + (Join-Path $fakeHome '.claude\skills\graphify\')),
        ('GLOBAL: ' + (Join-Path $fakeHome '.claude\CLAUDE.md')),
        ('GLOBAL: ' + (Join-Path $fakeHome '.gemini\config\skills\graphify\'))
    )
    $missing = @($expected | Where-Object { (Get-MatchCount $run.Stdout $_) -ne 1 })
    Add-Result 'setup prints each GLOBAL path written by graphify install' (($run.ExitCode -eq 0) -and ($missing.Count -eq 0)) ("exit={0} missing={1}" -f $run.ExitCode, ($missing -join ' / '))

    $configDir = Join-Path $workspace 'claude-config'
    $run = Invoke-SetupWithPath $workspace $pathValue '' @{ USERPROFILE = $fakeHome; CLAUDE_CONFIG_DIR = $configDir }
    $expected = @(
        ('GLOBAL: ' + (Join-Path $configDir 'skills\graphify\')),
        ('GLOBAL: ' + (Join-Path $configDir 'CLAUDE.md')),
        ('GLOBAL: ' + (Join-Path $fakeHome '.gemini\config\skills\graphify\'))
    )
    $missing = @($expected | Where-Object { (Get-MatchCount $run.Stdout $_) -ne 1 })
    Add-Result 'setup GLOBAL paths honor CLAUDE_CONFIG_DIR' (($run.ExitCode -eq 0) -and ($missing.Count -eq 0)) ("exit={0} missing={1}" -f $run.ExitCode, ($missing -join ' / '))
}

function Test-GraphifySkipCase {
    $workspace = New-GraphifyTestWorkspace
    $binDir = Join-Path $workspace 'bin'
    $logPath = Join-Path $workspace 'graphify-calls.log'
    New-GraphifyShim $binDir $logPath
    $run = Invoke-SetupWithPath $workspace ($binDir + ';' + $MinimalPath) '-SkipGraphifyInstall'
    $calls = @(Get-LogLines $logPath).Count
    $skipped = $run.Stdout.Contains('SKIP: graphify install (-SkipGraphifyInstall)')
    $noGlobal = -not $run.Stdout.Contains('GLOBAL:')
    $synced = (Get-MatchCount $run.Stdout 'hook command regenerated') -eq 2
    $passed = ($run.ExitCode -eq 0) -and ($calls -eq 0) -and $skipped -and $noGlobal -and $synced
    Add-Result 'setup -SkipGraphifyInstall never calls graphify' $passed ("exit={0} calls={1} skipped={2} no GLOBAL={3} hooks synced={4}" -f $run.ExitCode, $calls, $skipped, $noGlobal, $synced)
}

function Test-InheritedGraphifyUntouched {
    $calls = @(Get-LogLines $SentinelLog)
    Add-Result 'suite never calls graphify from inherited PATH' ($calls.Count -eq 0) ("calls={0} {1}" -f $calls.Count, ($calls -join ' / '))
}

$PosixShell = Find-PosixShell
$claudeCommand = Get-HookCommand (Join-Path $WorkspaceRoot '.claude\settings.json') 'hooks'
$antigravityCommand = Get-HookCommand (Join-Path $WorkspaceRoot '.agents\hooks.json') 'code-formatter'
$shells = @('cmd', 'powershell')
if ($PosixShell) { $shells += 'sh' } else { Add-Result 'sh available' $false 'no sh.exe or bash.exe found' }

try {
    New-SubprojectFixture
    New-GraphifyShim $SentinelBin $SentinelLog
    $env:PATH = $SentinelBin + ';' + $InheritedPath
    $ExpectedFormatted = Get-ExpectedFormatted
    $expectedCommand = Get-PrintedHookCommand $SetupScript
    Test-CommandInSync 'claude settings.json matches hook-launcher.ps1' $claudeCommand $expectedCommand
    Test-CommandInSync 'antigravity hooks.json matches hook-launcher.ps1' $antigravityCommand $expectedCommand
    Test-LineEndingIndependence $claudeCommand
    Test-AtomicHookUpdate $expectedCommand
    Test-GraphifyAbsentCase
    Test-GraphifyPresentCase
    Test-GraphifyFailureCases
    Test-GraphifyGlobalPathsCase
    Test-GraphifySkipCase

    $directories = [ordered]@{ root = $WorkspaceRoot; fixture = $Subproject }
    foreach ($shell in $shells) {
        foreach ($entry in $directories.GetEnumerator()) {
            Test-FormatCase "claude $shell $($entry.Key) env" $shell $claudeCommand $entry.Value 'claude' $WorkspaceRoot
            Test-FormatCase "claude $shell $($entry.Key) noenv" $shell $claudeCommand $entry.Value 'claude' $null
            Test-FormatCase "antigravity $shell $($entry.Key)" $shell $antigravityCommand $entry.Value 'antigravity' $null
        }
    }
    Test-FormatCase 'claude cmd outside-workspace-cwd env' 'cmd' $claudeCommand $env:SystemRoot 'claude' $WorkspaceRoot

    $markdown = New-Fixture '__hook_case_markdown.md' $MarkdownSource
    $markdownPayload = '{"tool_input":{"file_path":"' + $markdown.Replace('\', '\\') + '"}}'
    Test-NoOpCase 'markdown untouched' $claudeCommand $markdownPayload $markdown $MarkdownSource
    Test-NoOpCase 'invalid json exit 0' $claudeCommand '{not json' $null $null
    Test-NoOpCase 'empty stdin exit 0' $claudeCommand '' $null $null

    $outsideFixture = New-Fixture '__hook_case_outside_noenv.ts' $UnformattedSource
    $outsidePayload = '{"tool_input":{"file_path":"' + $outsideFixture.Replace('\', '\\') + '"}}'
    Test-NoOpCase 'outside-workspace-cwd noenv untouched' $claudeCommand $outsidePayload $outsideFixture $UnformattedSource $env:SystemRoot $null

    foreach ($broken in $BrokenFormatters.GetEnumerator()) { Test-BrokenFormatterCase $broken.Key $broken.Value $claudeCommand }
    Test-InheritedGraphifyUntouched
}
finally {
    $env:PATH = $InheritedPath
    foreach ($file in $CreatedFiles) { Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue }
    foreach ($directory in $TempDirectories) { Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item -LiteralPath $Subproject -Recurse -Force -ErrorAction SilentlyContinue
}

$leftovers = @(@($Subproject) + $TempDirectories | Where-Object { Test-Path -LiteralPath $_ })
Add-Result 'fixtures removed after run' ($leftovers.Count -eq 0) ("leftovers={0}" -f ($leftovers -join ','))

foreach ($result in $Results) { Write-Output ("{0}  {1,-50} {2}" -f $result.Result, $result.Case, $result.Detail) }
$failed = @($Results | Where-Object { $_.Result -ne 'PASS' }).Count
Write-Output ("{0} cases, {1} failed" -f $Results.Count, $failed)
if ($failed -gt 0) { exit 1 }
exit 0
