# Guia de Agentes do Projeto (AGENTS.md)

Este documento fornece as instruções definitivas, arquitetura e padrões operacionais para qualquer assistente de IA e agentes autônomos (OpenAI Codex, Gemini, Claude, Cursor, Copilot, Antigravity, etc.) neste projeto.

---

## 1. Mapeamento de Módulos e Componentes

Este projeto pode ser um projeto único ou um monorepo com múltiplos subprojetos independentes, cada um com seu próprio manifesto (`package.json`, `pyproject.toml`, `go.mod` ou equivalente) e seus próprios gates, declarados na seção 2. **Cada novo subprojeto adiciona uma linha nesta tabela e um bloco na seção 2.** Ao clonar este template, ainda não há nenhum subprojeto executável: a tabela lista só a infraestrutura de governança.

| Diretório / Pacote | Tecnologia | Função Principal |
| :--- | :--- | :--- |
| `.agents/` | AI Governance Engine | Regras, Personas, Skills, Workflows, Scripts e Hooks (fonte única) |
| `.claude/` | Claude Code | Wrappers de subagentes, comandos, `settings.json` (hook + permissões) e junction `skills` → `.agents/skills` |
| `docs/` | Auditoria Histórica | Prompts, Code Reviews, QA e Relatórios Pre-PR |
| `graphify-out/` | graphify | Grafo de conhecimento do projeto (`graph.json`, `GRAPH_REPORT.md`), gerado localmente, não versionado (está no `.gitignore`) e regenerado com `graphify update .` |

---

## 2. Comandos Mecânicos Obrigatórios (Cobertura ≥ 80%)

Os gates rodam **dentro do subprojeto afetado**.

### Modelo para cada novo subprojeto

Ainda não há subprojeto executável. Cada subprojeto novo declara aqui um bloco `### <subprojeto>/` com os comandos, rodados dentro dele:

| Gate | O que declarar |
| :--- | :--- |
| Formatação | comando de checagem do formatador local (ex.: `prettier --check`); em JS/TS, prettier instalado localmente, que o hook pós-edição aplica sozinho |
| Lint + tipos | comando único que falha com erro de lint ou de tipo |
| Testes + cobertura | comando de testes com threshold de 80% em lines/functions/branches/statements configurado no próprio projeto |
| Build | comando de build de produção |
| Teste real em runtime | como subir o serviço em background, quais URLs checar (incluindo `/health`) esperando `200`, e como encerrar o processo. No Windows, escreva `curl.exe` (em Windows PowerShell 5.1 `curl` é alias de `Invoke-WebRequest`); no Linux/macOS, `curl` |

### Todo o projeto

- **Sincronização do Grafo**: `graphify update .` (na raiz). O `graphify-out/` é local e não é versionado: num clone novo, ele só existe depois do primeiro `graphify update .`
- **Setup do ambiente de agentes** (uma vez por clone/PC, PowerShell 7 `pwsh` nos três sistemas): `pwsh -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup-agents.ps1` e a variável de ambiente de usuário `CONTEXT7_API_KEY`. O setup também regenera o comando do hook (`pwsh -EncodedCommand`) em `.claude/settings.json` e `.agents/hooks.json` a partir de `.agents/scripts/hook-launcher.ps1` (rode-o de novo sempre que editar o launcher, nunca edite o base64 à mão; um comando antigo `powershell ... -EncodedCommand` de versões anteriores é migrado automaticamente) e instala a skill global do graphify para Claude Code e Antigravity (`graphify install --platform claude` / `--platform antigravity`) quando o `graphify` estiver no PATH. Com o graphify ausente ou com exit diferente de zero, imprime `WARN` e segue com exit 0. Avisos em stderr com exit 0 contam como `OK`. **Esse passo grava fora do repositório**, em destinos do usuário que valem para todos os projetos, a partir de `$HOME`: `~/.claude/skills/graphify/`, `~/.claude/CLAUDE.md` (criado ou editado com uma seção `# graphify`, que entra em toda sessão do Claude Code) e `~/.gemini/config/skills/graphify/`. Com `CLAUDE_CONFIG_DIR` definida, os dois primeiros ficam dentro dela. O setup imprime uma linha `GLOBAL: <caminho>` por destino. Para não gravar nada global, rode o setup com `-SkipGraphifyInstall`. O link `.claude/skills` é uma junction no Windows (sem admin) e um symlink relativo no Linux/macOS.
- **Regressão do hook e do setup**: `pwsh -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/tests/post-tool-formatter.cases.ps1` (exit 0; no Windows testa cmd, sh (Git Bash), Windows PowerShell 5.1 e pwsh; no Linux/macOS testa sh, bash e pwsh — a partir da raiz e de dentro de um subprojeto de fixture temporário em `.agents/scripts/tests/.fixture-*`, ignorado pelo git e apagado no fim, com um shim determinístico de prettier (`prettier.cmd` no Windows, script executável nos demais) e de graphify (`graphify.cmd` / script executável) que não dependem de node, de python nem de rede). Os processos do setup rodam com PATH mínimo (`%SystemRoot%\System32` no Windows, `/usr/bin:/bin` no Linux/macOS, mais o shim quando o caso exige graphify), e um shim sentinela no PATH herdado garante que a suíte nunca chame o `graphify` real. Os casos do `review-opus.ps1` rodam numa pasta `rv<8 hex>` do diretório temporário do sistema, apagada no fim; no Windows, o `claude.exe` falso do caso da extensão fica uns 108 caracteres abaixo do `%TEMP%` e é compilado com o `csc.exe` do .NET Framework 4 (`Framework64` ou `Framework`), então esse caso só cabe no MAX_PATH (260) com um `%TEMP%` de até uns 150 caracteres, e sem `csc.exe` ele falha com `setup failed` enquanto o resto da suíte segue.

---

## 3. Pipeline de Agentes Especializados (`.agents/agents/`)

Roteamento, fluxo, invocação por ambiente (Claude Code: subagentes em `.claude/agents/` e `/implement` `/review` `/qa` `/bugfix` `/handoff`; Antigravity: os mesmos comandos em `.agents/workflows/`), separação de modelos e formatos de relatório: [`.agents/rules/agent-pipeline.md`](.agents/rules/agent-pipeline.md).

- `feature-implementer`: TDD (teste primeiro), Clean Code, cobertura ≥ 80%, teste real do projeto.
- `code-reviewer`: Auditoria mecânica independente sem editar código, checagem de teste real, parecer em `docs/reviews/`.
- `bug-fixer`: Reprodução obrigatória com teste vermelho antes de corrigir (Red -> Green), teste real de runtime.
- `qa-validator`: Validação de runtime, segurança e saúde dos serviços em execução real.

---

## 4. Regras Invioláveis do Repositório

1. **Fonte Única de Verdade**: Toda governança reside em `AGENTS.md`. Arquivos de IDEs atuam apenas como ponteiro leve.
2. **Cobertura de Testes**: Mínimo de 80% em qualquer alteração.
3. **Sem Comentários Óbvios**: Código autoexplicativo. Remoção compulsória de comentários redundantes e código morto nos arquivos alterados; fora do diff, vira nota no relatório (`.agents/rules/engineering-standards.md` §6).
4. **Auditoria de Prompts**: Todo prompt normalizado no `prompt-template.md` e registrado em `docs/prompts/`.
5. **Pre-PR Obrigatório**: Execução dos gates mecânicos com relatório persistido em `docs/pre-pr/` e exibido na resposta.
6. **Segurança**: Proibição de credenciais hardcoded e vazamento de dados sensíveis em logs. Chaves de MCP (ex.: `CONTEXT7_API_KEY`) vêm só de variável de ambiente, nunca de arquivo versionado.
7. **Teste Real em Runtime Obrigatório**: Ao final de cada mudança de código em subprojeto executável, rodar o projeto e validar endpoints via HTTP/curl. Mudança só de docs, regras ou config de agentes registra "N/A — sem mudança de código executável" (`.agents/rules/real-runtime-verification.md` §2.1).
8. **Protocolo de Melhoria Contínua**: Propor atualizações de governança via diff estruturado para aprovação humana.
9. **Autonomia de Personas**: O auditor (`code-reviewer`) não edita código de produção; correções iniciam com teste de reprodução (Red-to-Green).
