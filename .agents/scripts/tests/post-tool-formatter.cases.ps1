$ErrorActionPreference = 'Stop'

function Test-IsWindowsPlatform {
    $v = Get-Variable -Name 'IsWindows' -ErrorAction SilentlyContinue
    if ($null -ne $v) { return [bool]$v.Value }
    return [Environment]::OSVersion.Platform -eq [PlatformID]::Win32NT
}

function Join-Segments([string]$base, [string[]]$segments) {
    $result = $base
    foreach ($segment in $segments) { $result = Join-Path $result $segment }
    return $result
}

$OnWindows = Test-IsWindowsPlatform
$PathSep = [IO.Path]::PathSeparator
$DirSep = [IO.Path]::DirectorySeparatorChar

$Pwsh = 'pwsh'
$onPwsh = Get-Command pwsh -ErrorAction SilentlyContinue
if ($onPwsh) { $Pwsh = $onPwsh.Source }

$WorkspaceRoot = [IO.Path]::GetFullPath((Join-Segments $PSScriptRoot @('..', '..', '..'))).TrimEnd($DirSep)
$Subproject = Join-Path $PSScriptRoot ('.fixture-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$FixtureDir = Join-Path $Subproject 'src'
$PrettierName = 'prettier'
if ($OnWindows) { $PrettierName = 'prettier.cmd' }
$Prettier = Join-Segments $Subproject @('node_modules', '.bin', $PrettierName)
$SetupScript = Join-Segments $WorkspaceRoot @('.agents', 'scripts', 'setup-agents.ps1')
$HookLauncher = Join-Segments $WorkspaceRoot @('.agents', 'scripts', 'hook-launcher.ps1')
$ReviewScript = Join-Segments $WorkspaceRoot @('.agents', 'scripts', 'review-opus.ps1')
$FakeClaudeMarker = 'fake-claude-output'
$LegacyPowerShellExe = $null
if ($OnWindows) { $LegacyPowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe' }
$MinimalPath = '/usr/bin' + $PathSep + '/bin'
if ($OnWindows) { $MinimalPath = Join-Path $env:SystemRoot 'System32' }
$SentinelBin = Join-Path $Subproject 'inherited-path-bin'
$SentinelLog = Join-Path $Subproject 'inherited-graphify-calls.log'
$InheritedPath = $env:PATH
$UnformattedSource = "const  hookCase={alpha:1,beta:'two'}`nexport default   hookCase`n"
$ShimMarker = '// formatted by fixture prettier shim'
$ShimNewline = "`n"
if ($OnWindows) { $ShimNewline = "`r`n" }
$ShimExpected = $ShimMarker + $ShimNewline + $UnformattedSource
$WindowsPrettierShim = @'
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
$PosixPrettierShim = @'
#!/bin/sh
write=""
target=""
for arg in "$@"; do
  if [ "$arg" = "--write" ]; then
    write="1"
  fi
  target="$arg"
done
if [ -z "$write" ]; then
  exit 2
fi
if [ ! -f "$target" ]; then
  exit 3
fi
{
  echo "// formatted by fixture prettier shim"
  cat "$target"
} > "$target.shim"
mv -f "$target.shim" "$target"
'@
$MarkdownSource = "#   Title   `n`n*  item`n"
$NativeStderrCommand = "sh -c 'echo broken formatter 1>&2'"
if ($OnWindows) { $NativeStderrCommand = 'cmd /c "echo broken formatter 1>&2"' }
$BrokenFormatters = [ordered]@{
    'syntax error' = "if (`n"
    'throw' = "throw 'broken formatter'`n"
    'Write-Error' = "Write-Error 'broken formatter'`n"
    'native stderr' = "$NativeStderrCommand`nWrite-Output 'noise'`n"
}
$Results = New-Object System.Collections.Generic.List[object]
$CreatedFiles = New-Object System.Collections.Generic.List[string]
$TempDirectories = New-Object System.Collections.Generic.List[string]

function New-SubprojectFixture {
    New-Item -ItemType Directory -Path $FixtureDir, (Split-Path -Parent $Prettier) -Force | Out-Null
    if ($OnWindows) {
        [IO.File]::WriteAllText($Prettier, ($WindowsPrettierShim -replace "`r?`n", "`r`n"), (New-Object Text.ASCIIEncoding))
        return
    }
    [IO.File]::WriteAllText($Prettier, ($PosixPrettierShim -replace "`r?`n", "`n"), (New-Object Text.ASCIIEncoding))
    & chmod +x $Prettier
}

function Find-ShellBinary([string]$name) {
    $onPath = Get-Command $name -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }
    if (-not $OnWindows) { return $null }
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
        'bash' { return @{ File = $BashShell; Arguments = "-c `"$command`"" } }
        'powershell' { return @{ File = 'powershell.exe'; Arguments = "-NoProfile -NonInteractive -Command $command" } }
        'pwsh' { return @{ File = $Pwsh; Arguments = "-NoProfile -NonInteractive -Command $command" } }
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
    $run = Invoke-Hook 'pwsh' $command $workingDirectory $stdin $projectDir
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
    New-Item -ItemType Directory -Path (Join-Segments $root @('.agents', 'scripts')) -Force | Out-Null
    $TempDirectories.Add($root)
    return $root
}

function Write-AsciiFile([string]$path, [string]$content) {
    [IO.File]::WriteAllText($path, $content, (New-Object Text.UTF8Encoding($false)))
}

function Get-PrintedHookCommand([string]$setupScript) {
    return (& $Pwsh -NoProfile -ExecutionPolicy Bypass -File $setupScript -PrintHookCommand | Out-String).Trim()
}

function Test-LineEndingIndependence([string]$expected) {
    $normalized = [IO.File]::ReadAllText($HookLauncher) -replace "`r`n", "`n"
    $variants = [ordered]@{ LF = $normalized; CRLF = $normalized -replace "`n", "`r`n" }
    foreach ($variant in $variants.GetEnumerator()) {
        $scripts = Join-Segments (New-TempWorkspace) @('.agents', 'scripts')
        Copy-Item -LiteralPath $SetupScript -Destination $scripts
        Write-AsciiFile (Join-Path $scripts 'hook-launcher.ps1') $variant.Value
        $actual = Get-PrintedHookCommand (Join-Path $scripts 'setup-agents.ps1')
        Test-CommandInSync "$($variant.Key) launcher copy generates committed command" $actual $expected
    }
}

function Invoke-SetupWithPath([string]$workspace, [string]$pathValue, [string]$extraArguments = '', [hashtable]$environment = @{}) {
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Pwsh
    $info.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" {1}' -f (Join-Segments $workspace @('.agents', 'scripts', 'setup-agents.ps1')), $extraArguments).Trim()
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

function Invoke-SetupIn([string]$workspace) {
    return Invoke-SetupWithPath $workspace $MinimalPath
}

function Test-AtomicHookUpdate([string]$expected) {
    $workspace = New-TempWorkspace
    $scripts = Join-Segments $workspace @('.agents', 'scripts')
    Copy-Item -LiteralPath $SetupScript, $HookLauncher -Destination $scripts
    New-Item -ItemType Directory -Path (Join-Segments $workspace @('.agents', 'skills')), (Join-Path $workspace '.claude') -Force | Out-Null
    $settings = Join-Segments $workspace @('.claude', 'settings.json')
    $hooks = Join-Segments $workspace @('.agents', 'hooks.json')
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
    if ($OnWindows) { (Get-Item -LiteralPath $hooks).IsReadOnly = $true } else { & chattr +i $hooks }
    try {
        $run = Invoke-SetupIn $workspace
        $restored = [IO.File]::ReadAllText($settings) -ceq $settingsSource
        Add-Result 'setup write failure restores written file' (($run.ExitCode -eq 1) -and $restored) ("exit={0} settings.json restored={1}" -f $run.ExitCode, $restored)
    }
    finally {
        if ($OnWindows) { (Get-Item -LiteralPath $hooks).IsReadOnly = $false } else { & chattr -i $hooks }
    }

    $run = Invoke-SetupIn $workspace
    $synced = @($settings, $hooks | Where-Object { [IO.File]::ReadAllText($_).Contains('"command":"' + $expected + '"') }).Count
    Add-Result 'setup migrates legacy powershell hook command to pwsh syntax' (($run.ExitCode -eq 0) -and ($synced -eq 2) -and $expected.StartsWith('pwsh ')) ("exit={0} files synced={1} expected starts with pwsh={2}" -f $run.ExitCode, $synced, $expected.StartsWith('pwsh '))
}

function Test-BrokenFormatterCase([string]$mode, [string]$source, [string]$command) {
    $workspace = New-TempWorkspace
    Write-AsciiFile (Join-Segments $workspace @('.agents', 'scripts', 'post-tool-formatter.ps1')) $source
    $fixture = New-Fixture ("__hook_case_broken_{0}.ts" -f ($mode -replace '[^A-Za-z0-9]', '_')) $UnformattedSource
    $payload = '{"tool_input":{"file_path":"' + $fixture.Replace('\', '\\') + '"}}'
    $projectDirForBroken = $env:SystemRoot
    if (-not $OnWindows) { $projectDirForBroken = '/tmp' }
    Test-NoOpCase "broken formatter: $mode" $command $payload $fixture $UnformattedSource $projectDirForBroken $workspace
}

function New-GraphifyTestWorkspace {
    $workspace = New-TempWorkspace
    $scripts = Join-Segments $workspace @('.agents', 'scripts')
    Copy-Item -LiteralPath $SetupScript, $HookLauncher -Destination $scripts
    New-Item -ItemType Directory -Path (Join-Segments $workspace @('.agents', 'skills')), (Join-Path $workspace '.claude') -Force | Out-Null
    $settings = Join-Segments $workspace @('.claude', 'settings.json')
    $hooks = Join-Segments $workspace @('.agents', 'hooks.json')
    $staleHook = '{"type":"command","command":"powershell -NoProfile -File .agents/scripts/post-tool-formatter.ps1"}'
    Write-AsciiFile $settings ('{"hooks":{"PostToolUse":[{"matcher":"Edit|Write","hooks":[' + $staleHook + ']}]}}')
    Write-AsciiFile $hooks ('{"code-formatter":{"PostToolUse":[{"hooks":[' + $staleHook + ']}]}}')
    return $workspace
}

function New-GraphifyShim([string]$binDir, [string]$logPath, [string]$extraLines = '', [int]$exitCode = 0) {
    New-Item -ItemType Directory -Path $binDir -Force | Out-Null
    if ($OnWindows) {
        $shim = "@echo off`r`n>> `"$logPath`" echo %*`r`n$extraLines" + "exit /b $exitCode`r`n"
        [IO.File]::WriteAllText((Join-Path $binDir 'graphify.cmd'), $shim, (New-Object Text.ASCIIEncoding))
        return
    }
    $shimPath = Join-Path $binDir 'graphify'
    $body = "#!/bin/sh`necho `"`$*`" >> `"$logPath`"`n$extraLines" + "exit $exitCode`n"
    [IO.File]::WriteAllText($shimPath, $body, (New-Object Text.ASCIIEncoding))
    & chmod +x $shimPath
}

function Get-GraphifyStderrLine([string]$message) {
    if ($OnWindows) { return "echo $message 1>&2`r`n" }
    return "echo `"$message`" 1>&2`n"
}

function Get-LogLines([string]$logPath) {
    if (-not (Test-Path -LiteralPath $logPath)) { return @() }
    return @(Get-Content -LiteralPath $logPath | ForEach-Object { $_.Trim() } | Where-Object { $_ })
}

function Get-MatchCount([string]$text, [string]$literal) {
    return ([regex]::Matches($text, [regex]::Escape($literal))).Count
}

function Test-GraphifyAbsentCase {
    $workspace = New-GraphifyTestWorkspace
    $run = Invoke-SetupWithPath $workspace $MinimalPath
    $warned = $run.Stdout -match 'graphify not found on PATH'
    $expectedHint = 'pipx install "graphifyy[mcp]"'
    if ($OnWindows) { $expectedHint = 'pip install "graphifyy[mcp]"' }
    $hintOk = $run.Stdout.Contains('Install with: ' + $expectedHint)
    Add-Result 'setup warns when graphify missing from PATH' (($run.ExitCode -eq 0) -and $warned -and $hintOk) ("exit={0} warned={1} hint for this OS={2} stdout={3}" -f $run.ExitCode, $warned, $hintOk, $run.Stdout)
}

function Get-ReadmeGraphifyCommands {
    $readme = [IO.File]::ReadAllText((Join-Path $WorkspaceRoot 'README.md'))
    $commands = @()
    $blocks = [regex]::Matches($readme, '(?s)```json\r?\n(.*?)```')
    for ($index = 0; $index -lt $blocks.Count; $index++) {
        $block = $blocks[$index]
        try { $config = $block.Groups[1].Value | ConvertFrom-Json }
        catch {
            $line = ($readme.Substring(0, $block.Index) -split "`n").Count
            Add-Result ("README json block {0} (line {1}) parses as strict JSON" -f ($index + 1), $line) $false ('parse failed: ' + $_.Exception.Message)
            continue
        }
        if ($config.mcpServers -and $config.mcpServers.graphify) { $commands += [string]$config.mcpServers.graphify.command }
    }
    return ,$commands
}

function Test-GraphifyMcpCommandConsistency {
    $mcp = [IO.File]::ReadAllText((Join-Path $WorkspaceRoot '.mcp.json')) | ConvertFrom-Json
    $server = $mcp.mcpServers.graphify
    $readmeCommands = Get-ReadmeGraphifyCommands
    $mismatched = @($readmeCommands | Where-Object { $_ -cne $server.command })
    $argsOk = (@($server.args) -join ' ') -ceq 'graphify-out/graph.json'
    $passed = ($server.command -ceq 'graphify-mcp') -and $argsOk -and ($readmeCommands.Count -ge 2) -and ($mismatched.Count -eq 0)
    Add-Result '.mcp.json and README examples start graphify MCP with graphify-mcp' $passed ("mcp.json={0} {1} readme={2}" -f $server.command, ($server.args -join ' '), ($readmeCommands -join ','))
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
    $pathValue = $binDir + $PathSep + $MinimalPath
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
    $linkOk = $run2.Stdout.Contains('OK: .claude/skills already points to .agents/skills')
    $hooksOk = (Get-MatchCount $run2.Stdout 'hook command is up to date') -eq 2
    $passed = ($run2.ExitCode -eq 0) -and $onceAgain -and $linkOk -and $hooksOk
    Add-Result 'setup graphify step is idempotent on second run' $passed ("exit={0} total calls={1} second run calls={2} link ok={3} hooks up to date={4}" -f $run2.ExitCode, $all.Count, $second.Count, $linkOk, $hooksOk)
}

function Test-GraphifyFailureCase([string]$name, [string]$extraLines, [int]$exitCode, [string[]]$expectedLines) {
    $workspace = New-GraphifyTestWorkspace
    $binDir = Join-Path $workspace 'bin'
    $logPath = Join-Path $workspace 'graphify-calls.log'
    New-GraphifyShim $binDir $logPath $extraLines $exitCode
    $run = Invoke-SetupWithPath $workspace ($binDir + $PathSep + $MinimalPath)
    $missing = @($expectedLines | Where-Object { -not $run.Stdout.Contains($_) })
    $calls = @(Get-LogLines $logPath).Count
    $passed = ($run.ExitCode -eq 0) -and ($missing.Count -eq 0) -and ($calls -eq 2)
    Add-Result $name $passed ("exit={0} calls={1} missing={2} stderr={3}" -f $run.ExitCode, $calls, ($missing -join ' / '), $run.Stderr)
}

function Test-GraphifyFailureCases {
    Test-GraphifyFailureCase 'setup survives graphify stderr with exit 0' (Get-GraphifyStderrLine 'graphify warning') 0 @('OK: graphify install --platform claude', 'OK: graphify install --platform antigravity')
    Test-GraphifyFailureCase 'setup warns and exits 0 when graphify exits 3' (Get-GraphifyStderrLine 'graphify failure') 3 @('WARN: graphify install --platform claude exited with code 3', 'WARN: graphify install --platform antigravity exited with code 3')
}

function Test-GraphifyGlobalPathsCase {
    $workspace = New-GraphifyTestWorkspace
    $binDir = Join-Path $workspace 'bin'
    $logPath = Join-Path $workspace 'graphify-calls.log'
    New-GraphifyShim $binDir $logPath
    $fakeHome = Join-Path $workspace 'home'
    $pathValue = $binDir + $PathSep + $MinimalPath
    $run = Invoke-SetupWithPath $workspace $pathValue '' @{ HOME = $fakeHome; USERPROFILE = $fakeHome }
    $expected = @(
        ('GLOBAL: ' + (Join-Segments $fakeHome @('.claude', 'skills', 'graphify')) + $DirSep),
        ('GLOBAL: ' + (Join-Segments $fakeHome @('.claude', 'CLAUDE.md'))),
        ('GLOBAL: ' + (Join-Segments $fakeHome @('.gemini', 'config', 'skills', 'graphify')) + $DirSep)
    )
    $missing = @($expected | Where-Object { (Get-MatchCount $run.Stdout $_) -ne 1 })
    Add-Result 'setup prints each GLOBAL path written by graphify install' (($run.ExitCode -eq 0) -and ($missing.Count -eq 0)) ("exit={0} missing={1}" -f $run.ExitCode, ($missing -join ' / '))

    $configDir = Join-Path $workspace 'claude-config'
    $run = Invoke-SetupWithPath $workspace $pathValue '' @{ HOME = $fakeHome; USERPROFILE = $fakeHome; CLAUDE_CONFIG_DIR = $configDir }
    $expected = @(
        ('GLOBAL: ' + (Join-Segments $configDir @('skills', 'graphify')) + $DirSep),
        ('GLOBAL: ' + (Join-Path $configDir 'CLAUDE.md')),
        ('GLOBAL: ' + (Join-Segments $fakeHome @('.gemini', 'config', 'skills', 'graphify')) + $DirSep)
    )
    $missing = @($expected | Where-Object { (Get-MatchCount $run.Stdout $_) -ne 1 })
    Add-Result 'setup GLOBAL paths honor CLAUDE_CONFIG_DIR' (($run.ExitCode -eq 0) -and ($missing.Count -eq 0)) ("exit={0} missing={1}" -f $run.ExitCode, ($missing -join ' / '))
}

function Test-GraphifySkipCase {
    $workspace = New-GraphifyTestWorkspace
    $binDir = Join-Path $workspace 'bin'
    $logPath = Join-Path $workspace 'graphify-calls.log'
    New-GraphifyShim $binDir $logPath
    $run = Invoke-SetupWithPath $workspace ($binDir + $PathSep + $MinimalPath) '-SkipGraphifyInstall'
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

function Test-SkillsLinkLifecycle {
    $workspace = New-GraphifyTestWorkspace
    $link = Join-Segments $workspace @('.claude', 'skills')
    $target = Join-Segments $workspace @('.agents', 'skills')

    $run = Invoke-SetupWithPath $workspace $MinimalPath '-SkipGraphifyInstall'
    $exists = Test-Path -LiteralPath $link
    $expectedType = 'SymbolicLink'
    if ($OnWindows) { $expectedType = 'Junction' }
    $actualType = $null
    $resolvedOk = $false
    if ($exists) {
        $item = Get-Item -LiteralPath $link -Force
        $actualType = [string]$item.LinkType
        $rawTarget = [string]@($item.Target)[0]
        if ($OnWindows) { $resolvedOk = ($rawTarget.TrimEnd('\') -ieq $target.TrimEnd('\')) }
        else {
            $resolvedBase = if ([IO.Path]::IsPathRooted($rawTarget)) { $rawTarget } else { Join-Path (Split-Path -Parent $link) $rawTarget }
            $resolved = [IO.Path]::GetFullPath($resolvedBase)
            $resolvedOk = ($resolved.TrimEnd('/') -ceq $target.TrimEnd('/'))
        }
    }
    Add-Result 'setup creates skills link with OS-appropriate type' (($run.ExitCode -eq 0) -and $exists -and ($actualType -eq $expectedType)) ("exit={0} exists={1} type={2} expected={3}" -f $run.ExitCode, $exists, $actualType, $expectedType)
    Add-Result 'setup skills link resolves to .agents/skills' $resolvedOk ("target resolved correctly={0}" -f $resolvedOk)

    $run2 = Invoke-SetupWithPath $workspace $MinimalPath '-SkipGraphifyInstall'
    $stillLink = Test-Path -LiteralPath $link
    $upToDate = $run2.Stdout.Contains('OK: .claude/skills already points to .agents/skills')
    Add-Result 'setup skills link creation is idempotent' (($run2.ExitCode -eq 0) -and $stillLink -and $upToDate) ("exit={0} stillLink={1} upToDate={2}" -f $run2.ExitCode, $stillLink, $upToDate)
}

function Test-SetupUnderLegacyPowerShell {
    if (-not $OnWindows) { return }
    $workspace = New-GraphifyTestWorkspace
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $LegacyPowerShellExe
    $info.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -SkipGraphifyInstall' -f (Join-Segments $workspace @('.agents', 'scripts', 'setup-agents.ps1')))
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $process = [Diagnostics.Process]::Start($info)
    $stdout = $process.StandardOutput.ReadToEnd()
    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    $link = Join-Segments $workspace @('.claude', 'skills')
    $usesPwsh = (Get-HookCommand (Join-Segments $workspace @('.claude', 'settings.json')) 'hooks').StartsWith('pwsh ')
    $passed = ($process.ExitCode -eq 0) -and (Test-Path -LiteralPath $link) -and $usesPwsh
    Add-Result 'setup-agents.ps1 runs under Windows PowerShell 5.1' $passed ("exit={0} link exists={1} uses pwsh={2} stdout={3} stderr={4}" -f $process.ExitCode, (Test-Path -LiteralPath $link), $usesPwsh, $stdout.Trim(), $stderr.Trim())
}

function Test-CurrentPlatformDetection {
    $viaRuntimeInformation = [Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([Runtime.InteropServices.OSPlatform]::Windows)
    Add-Result 'suite platform detection matches RuntimeInformation.IsOSPlatform' ($OnWindows -eq $viaRuntimeInformation) ("Test-IsWindowsPlatform={0} RuntimeInformation={1}" -f $OnWindows, $viaRuntimeInformation)
    Add-Result 'prettier shim binary name matches current OS' ((-not $OnWindows -and $PrettierName -eq 'prettier') -or ($OnWindows -and $PrettierName -eq 'prettier.cmd')) $PrettierName
}

function Test-HookCommandUsesPwshOnCurrentOS([string]$command) {
    Add-Result 'hook command uses pwsh regardless of current OS' ($command.StartsWith('pwsh ')) $command.Substring(0, [Math]::Min(60, $command.Length))
}

function Test-ShellSetMatchesCurrentOS([string[]]$shellSet) {
    if ($OnWindows) {
        $ok = ($shellSet -contains 'cmd') -and ($shellSet -contains 'pwsh')
    } else {
        $ok = ($shellSet -contains 'sh') -and ($shellSet -contains 'pwsh') -and (-not ($shellSet -contains 'cmd')) -and (-not ($shellSet -contains 'powershell'))
    }
    Add-Result 'suite exercises the OS-appropriate shell set' $ok ("shells={0}" -f ($shellSet -join ','))
}

function New-ReviewWorkspace {
    $workspace = Join-Path ([IO.Path]::GetTempPath()) ('rv' + [guid]::NewGuid().ToString('N').Substring(0, 8))
    $scripts = Join-Segments $workspace @('.agents', 'scripts')
    $TempDirectories.Add($workspace)
    New-Item -ItemType Directory -Path $scripts, (Join-Path $workspace 'home'), (Join-Path $workspace 'bin') -Force | Out-Null
    Copy-Item -LiteralPath $ReviewScript -Destination $scripts
    return $workspace
}

function Write-PosixExecutable([string]$path, [string]$content) {
    [IO.File]::WriteAllText($path, ($content -replace "`r?`n", "`n"), (New-Object Text.ASCIIEncoding))
    & chmod +x $path
}

function New-ClaudePathShim([string]$binDir) {
    if ($OnWindows) {
        $shim = "@echo off`r`necho $FakeClaudeMarker from PATH shim`r`nexit /b 0`r`n"
        [IO.File]::WriteAllText((Join-Path $binDir 'claude.cmd'), $shim, (New-Object Text.ASCIIEncoding))
        return
    }
    Write-PosixExecutable (Join-Path $binDir 'claude') "#!/bin/sh`necho `"$FakeClaudeMarker from PATH shim`"`n"
}

function Find-Csc {
    foreach ($framework in @('Framework64', 'Framework')) {
        $candidate = Join-Segments $env:SystemRoot @('Microsoft.NET', $framework, 'v4.0.30319', 'csc.exe')
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    return $null
}

function Get-FakeClaudeExe {
    $exe = Join-Path $Subproject 'fake-claude.exe'
    if (Test-Path -LiteralPath $exe) { return $exe }
    $csc = Find-Csc
    if (-not $csc) { throw 'csc.exe not found in %SystemRoot%\Microsoft.NET\Framework64 or Framework (v4.0.30319)' }
    $source = Join-Path $Subproject 'fake-claude.cs'
    $program = 'class FakeClaude { static void Main() { System.Console.WriteLine("' + $FakeClaudeMarker + ' from " + System.Reflection.Assembly.GetEntryAssembly().Location); } }'
    Write-AsciiFile $source $program
    & $csc /nologo /target:exe "/out:$exe" $source | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "csc failed to build the fake claude.exe: exit $LASTEXITCODE" }
    return $exe
}

function New-FakeClaudeExtension([string]$fakeHome, [string]$folderName, [switch]$Placeholder) {
    $binaryDir = Join-Segments $fakeHome @('.vscode', 'extensions', $folderName, 'resources', 'native-binary')
    New-Item -ItemType Directory -Path $binaryDir -Force | Out-Null
    if ($Placeholder) {
        $binaryName = 'claude'
        if ($OnWindows) { $binaryName = 'claude.exe' }
        Write-AsciiFile (Join-Path $binaryDir $binaryName) 'placeholder, never executed'
        return
    }
    if ($OnWindows) {
        Copy-Item -LiteralPath (Get-FakeClaudeExe) -Destination (Join-Path $binaryDir 'claude.exe')
        return
    }
    Write-PosixExecutable (Join-Path $binaryDir 'claude') "#!/bin/sh`necho `"$FakeClaudeMarker from `$0`"`n"
}

function Invoke-ReviewOpus([string]$workspace, [string]$pathValue, [string]$slug) {
    $fakeHome = Join-Path $workspace 'home'
    $info = New-Object Diagnostics.ProcessStartInfo
    $info.FileName = $Pwsh
    $info.Arguments = ('-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Slug {1}' -f (Join-Segments $workspace @('.agents', 'scripts', 'review-opus.ps1')), $slug)
    $info.UseShellExecute = $false
    $info.RedirectStandardInput = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $info.EnvironmentVariables['PATH'] = $pathValue
    $info.EnvironmentVariables['HOME'] = $fakeHome
    $info.EnvironmentVariables['USERPROFILE'] = $fakeHome
    $process = [Diagnostics.Process]::Start($info)
    $process.StandardInput.Close()
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit(60000)) { $process.Kill(); return @{ ExitCode = 'timeout'; Stdout = ''; Stderr = ''; Report = '' } }
    $reportFile = Get-ChildItem -LiteralPath (Join-Segments $workspace @('docs', 'reviews')) -Filter ('*_{0}-review.md' -f $slug) -ErrorAction SilentlyContinue | Select-Object -First 1
    $report = ''
    if ($reportFile) { $report = [IO.File]::ReadAllText($reportFile.FullName) }
    $literalBackslashDir = (-not $OnWindows) -and [IO.Directory]::Exists($workspace + '/docs\reviews')
    return @{ ExitCode = $process.ExitCode; Stdout = $stdoutTask.Result.Trim(); Stderr = $stderrTask.Result.Trim(); Report = $report; LiteralBackslashDir = $literalBackslashDir }
}

function Add-SetupFailure([string]$name, [Management.Automation.ErrorRecord]$record) {
    Add-Result $name $false ('setup failed: ' + $record.Exception.Message)
}

function Test-ReviewOpusNoClaude {
    $name = 'review-opus without claude reports NOT REVIEWED exit 2'
    try { $workspace = New-ReviewWorkspace }
    catch { Add-SetupFailure $name $_; return }
    $run = Invoke-ReviewOpus $workspace $MinimalPath 'no-claude'
    $notReviewed = $run.Report.Contains('NOT REVIEWED') -and $run.Stdout.Contains('NOT REVIEWED')
    $passed = ($run.ExitCode -eq 2) -and $notReviewed -and (-not $run.LiteralBackslashDir)
    Add-Result $name $passed ("exit={0} not reviewed={1} literal docs\reviews dir={2} stderr={3}" -f $run.ExitCode, $notReviewed, $run.LiteralBackslashDir, $run.Stderr)
}

function Test-ReviewOpusPathShim {
    $name = 'review-opus prefers claude shim on PATH'
    try {
        $workspace = New-ReviewWorkspace
        $binDir = Join-Path $workspace 'bin'
        New-ClaudePathShim $binDir
        New-FakeClaudeExtension (Join-Path $workspace 'home') 'anthropic.claude-code-9.9.9' -Placeholder
    }
    catch { Add-SetupFailure $name $_; return }
    $run = Invoke-ReviewOpus $workspace ($binDir + $PathSep + $MinimalPath) 'path-shim'
    $fromShim = $run.Report.Contains("$FakeClaudeMarker from PATH shim")
    Add-Result $name (($run.ExitCode -eq 0) -and $fromShim) ("exit={0} report from PATH shim={1} stderr={2}" -f $run.ExitCode, $fromShim, $run.Stderr)
}

function Test-ReviewOpusHighestExtension {
    $name = 'review-opus picks highest extension version'
    try {
        $workspace = New-ReviewWorkspace
        $fakeHome = Join-Path $workspace 'home'
        $suffix = '-linux-x64'
        if ($OnWindows) { $suffix = '-win32-x64' }
        New-FakeClaudeExtension $fakeHome 'anthropic.claude-code-2.9.1'
        New-FakeClaudeExtension $fakeHome ('anthropic.claude-code-2.10.0' + $suffix)
    }
    catch { Add-SetupFailure $name $_; return }
    $run = Invoke-ReviewOpus $workspace $MinimalPath 'extension'
    $highest = $run.Report.Contains("$FakeClaudeMarker from ") -and $run.Report.Contains('anthropic.claude-code-2.10.0') -and (-not $run.Report.Contains('anthropic.claude-code-2.9.1'))
    $picked = [regex]::Match($run.Report, 'anthropic\.claude-code-[^\\/]+').Value
    Add-Result $name (($run.ExitCode -eq 0) -and $highest) ("exit={0} picked={1} stderr={2}" -f $run.ExitCode, $picked, $run.Stderr)
}

function Test-ReviewOpusCases {
    Test-ReviewOpusNoClaude
    Test-ReviewOpusPathShim
    Test-ReviewOpusHighestExtension
}

$PosixShell = Find-ShellBinary 'sh'
$BashShell = $null
if (-not $OnWindows) { $BashShell = Find-ShellBinary 'bash' }
$claudeCommand = Get-HookCommand (Join-Segments $WorkspaceRoot @('.claude', 'settings.json')) 'hooks'
$antigravityCommand = Get-HookCommand (Join-Segments $WorkspaceRoot @('.agents', 'hooks.json')) 'code-formatter'
$shells = @()
if ($OnWindows) {
    $shells = @('cmd')
    if ($PosixShell) { $shells += 'sh' } else { Add-Result 'sh available' $false 'no sh.exe or bash.exe found (Git Bash)' }
    $shells += @('powershell', 'pwsh')
} else {
    if ($PosixShell) { $shells += 'sh' } else { Add-Result 'sh available' $false 'no sh on PATH' }
    if ($BashShell) { $shells += 'bash' } else { Add-Result 'bash available' $false 'no bash on PATH' }
    $shells += 'pwsh'
}

try {
    New-SubprojectFixture
    New-GraphifyShim $SentinelBin $SentinelLog
    $env:PATH = $SentinelBin + $PathSep + $InheritedPath
    $ExpectedFormatted = Get-ExpectedFormatted
    $expectedCommand = Get-PrintedHookCommand $SetupScript
    Test-CurrentPlatformDetection
    Test-HookCommandUsesPwshOnCurrentOS $expectedCommand
    Test-ShellSetMatchesCurrentOS $shells
    Test-CommandInSync 'claude settings.json matches hook-launcher.ps1' $claudeCommand $expectedCommand
    Test-CommandInSync 'antigravity hooks.json matches hook-launcher.ps1' $antigravityCommand $expectedCommand
    Test-LineEndingIndependence $claudeCommand
    Test-AtomicHookUpdate $expectedCommand
    Test-SetupUnderLegacyPowerShell
    Test-SkillsLinkLifecycle
    Test-GraphifyAbsentCase
    Test-GraphifyMcpCommandConsistency
    Test-GraphifyPresentCase
    Test-GraphifyFailureCases
    Test-GraphifyGlobalPathsCase
    Test-GraphifySkipCase
    Test-ReviewOpusCases

    $directories = [ordered]@{ root = $WorkspaceRoot; fixture = $Subproject }
    foreach ($shell in $shells) {
        foreach ($entry in $directories.GetEnumerator()) {
            Test-FormatCase "claude $shell $($entry.Key) env" $shell $claudeCommand $entry.Value 'claude' $WorkspaceRoot
            Test-FormatCase "claude $shell $($entry.Key) noenv" $shell $claudeCommand $entry.Value 'claude' $null
            Test-FormatCase "antigravity $shell $($entry.Key)" $shell $antigravityCommand $entry.Value 'antigravity' $null
        }
    }
    $outsideDir = $env:SystemRoot
    if (-not $OnWindows) { $outsideDir = '/tmp' }
    Test-FormatCase "claude $($shells[0]) outside-workspace-cwd env" $shells[0] $claudeCommand $outsideDir 'claude' $WorkspaceRoot

    $markdown = New-Fixture '__hook_case_markdown.md' $MarkdownSource
    $markdownPayload = '{"tool_input":{"file_path":"' + $markdown.Replace('\', '\\') + '"}}'
    Test-NoOpCase 'markdown untouched' $claudeCommand $markdownPayload $markdown $MarkdownSource
    Test-NoOpCase 'invalid json exit 0' $claudeCommand '{not json' $null $null
    Test-NoOpCase 'empty stdin exit 0' $claudeCommand '' $null $null

    $outsideFixture = New-Fixture '__hook_case_outside_noenv.ts' $UnformattedSource
    $outsidePayload = '{"tool_input":{"file_path":"' + $outsideFixture.Replace('\', '\\') + '"}}'
    Test-NoOpCase 'outside-workspace-cwd noenv untouched' $claudeCommand $outsidePayload $outsideFixture $UnformattedSource $outsideDir $null

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
