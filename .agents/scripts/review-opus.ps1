param(
    [string]$Slug = "review",
    [string]$Context = ""
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [Text.Encoding]::UTF8
$root = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
Set-Location $root

function Find-ClaudeCli {
    $onPath = Get-Command claude -ErrorAction SilentlyContinue
    if ($onPath) { return $onPath.Source }

    $extensionRoots = @(
        "$env:USERPROFILE\.antigravity-ide\extensions",
        "$env:USERPROFILE\.antigravity\extensions",
        "$env:USERPROFILE\.vscode\extensions",
        "$env:USERPROFILE\.cursor\extensions"
    )
    foreach ($extensionRoot in $extensionRoots) {
        $candidate = Get-ChildItem $extensionRoot -Directory -Filter "anthropic.claude-code-*" -ErrorAction SilentlyContinue |
            Sort-Object { [version]($_.Name -replace '^anthropic\.claude-code-([\d\.]+).*$', '$1') } -Descending |
            ForEach-Object { Join-Path $_.FullName "resources\native-binary\claude.exe" } |
            Where-Object { Test-Path $_ } |
            Select-Object -First 1
        if ($candidate) { return $candidate }
    }
    return $null
}

$date = Get-Date -Format "yyyy-MM-dd"
$reportDir = Join-Path $root "docs\reviews"
$reportPath = Join-Path $reportDir "$($date)_$($Slug)-review.md"
New-Item -ItemType Directory -Force $reportDir | Out-Null

$claude = Find-ClaudeCli
if (-not $claude) {
    $notReviewed = @"
# Review: $Slug

- **Veredito**: NOT REVIEWED
- **Motivo**: CLI do Claude nao encontrada (PATH nem extensao anthropic.claude-code na Antigravity IDE, VS Code ou Cursor).
- **Proximo passo**: rodar /review no Claude Code ou, como fallback, /review no Antigravity registrando "mesmo modelo do implementador".
"@
    Set-Content -Path $reportPath -Value $notReviewed -Encoding utf8
    Write-Output "NOT REVIEWED - CLI do Claude nao encontrada. Relatorio: $reportPath"
    exit 2
}

$prompt = @"
Voce e o code-reviewer deste projeto, rodando em modo somente leitura.
Leia e siga .agents/agents/code-reviewer.md, .agents/rules/agent-pipeline.md e AGENTS.md.
Revise o diff atual do projeto. Contexto do pedido (criterios de aceite): $Context
Nao edite nem crie arquivos. Imprima como resposta final APENAS o relatorio completo em markdown, no formato de review de .agents/rules/agent-pipeline.md, com a linha "- **Revisado por**: claude opus (headless, a partir do Antigravity IDE)".
"@

$output = & $claude -p $prompt --model opus --allowedTools "Read" "Grep" "Glob" "Bash" "PowerShell" --disallowedTools "Edit" "Write" "NotebookEdit"
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0 -or -not $output) {
    $failed = @"
# Review: $Slug

- **Veredito**: NOT REVIEWED
- **Motivo**: claude -p saiu com codigo $exitCode.
"@
    Set-Content -Path $reportPath -Value $failed -Encoding utf8
    Write-Output "NOT REVIEWED - claude saiu com codigo $exitCode. Relatorio: $reportPath"
    exit 2
}

Set-Content -Path $reportPath -Value ($output -join "`n") -Encoding utf8
Write-Output "Relatorio: $reportPath"
Select-String -Path $reportPath -Pattern "NOT REVIEWED|APPROVED|REJECTED" | Select-Object -First 1 | ForEach-Object { $_.Line }
