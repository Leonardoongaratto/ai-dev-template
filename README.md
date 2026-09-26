# ai-dev-template

Template de repositório com uma governança de agentes de IA pronta para uso: papéis especializados (implementação, revisão, QA, correção de bugs), regras de engenharia, gates mecânicos obrigatórios (formatação, lint + tipos, testes com cobertura ≥ 80%, build, teste real em runtime), hooks de formatação automática e integração com os MCPs `context7` e `graphify`. Funciona com Claude Code e com Antigravity/Gemini no mesmo repositório, com uma única fonte de verdade (`AGENTS.md`).

Este template **não traz nenhum subprojeto**: ele é o esqueleto de governança que você aplica em cima de qualquer stack (Node, Python, Go, Rust, etc.), em um projeto único ou em um monorepo.

**Compatibilidade**: Windows, Linux e macOS, com PowerShell 7 (`pwsh`) como runtime único dos scripts em todos eles — um só conjunto de arquivos versionados, sem configuração por sistema operacional. Testado neste repositório em Windows e em Ubuntu (WSL2); **macOS não foi verificado** (sem máquina disponível para teste), mas o código é portável e segue os mesmos caminhos (symlink relativo, `$HOME`, `pwsh`) usados no Linux.

---

## 1. O que é

- **`AGENTS.md`**: fonte única de verdade para qualquer assistente de IA — mapeamento de módulos, comandos mecânicos obrigatórios, pipeline de agentes e regras invioláveis do repositório.
- **`CLAUDE.md` / `GEMINI.md`**: ponteiros leves que só importam `AGENTS.md`, para não duplicar regras e economizar tokens de contexto.
- **`.agents/`**: as definições que valem para qualquer ferramenta — regras (`rules/`), os quatro papéis (`agents/`), a skill `pre-pr` (`skills/pre-pr/`), os workflows do Antigravity (`workflows/`) e os scripts de automação (`scripts/`).
- **`.claude/`**: a integração específica do Claude Code — wrappers de subagentes (`agents/`), comandos de barra (`commands/`) e `settings.json` (hook de formatação + permissões). A pasta `.claude/skills` é um link para `.agents/skills` (junction no Windows, symlink relativo no Linux/macOS), criado pelo setup.
- **`docs/`**: histórico vivo e versionado de prompts, revisões, QA e relatórios Pre-PR (`prompts/`, `reviews/`, `pre-pr/`, `qa/`), cada um começando só com um `.gitkeep`.

---

## 2. Requisitos

Este template roda em **Windows, Linux e macOS**, com **PowerShell 7 (`pwsh`)** como runtime único dos scripts de automação (`.ps1`) nos três sistemas — inclusive no Windows, no lugar do Windows PowerShell 5.1 (`powershell`). Um único conjunto de arquivos versionados serve aos três; nada de configuração por sistema operacional.

| Requisito | Windows | Linux | macOS |
| --- | --- | --- | --- |
| PowerShell 7 (`pwsh`) | `winget install --id Microsoft.PowerShell --source winget` | pacote/instalador oficial da Microsoft para a distro (a distro pode não ter pacote `apt` para toda versão — nesse caso use o tarball oficial ou `snap install powershell --classic`); ver [learn.microsoft.com/powershell/scripting/install](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux) | `brew install --cask powershell` |
| Git | `winget install --id Git.Git` | `apt install git` / gerenciador da distro | `brew install git` |
| Node.js (só se algum subprojeto for JS/TS, para o Prettier local do hook) | `winget install --id OpenJS.NodeJS.LTS` | `apt install nodejs npm` / `nvm` | `brew install node` |
| `graphify` (pacote `graphifyy[mcp]` — o extra `mcp` é obrigatório para o servidor MCP) | Python 3 (`winget install --id Python.Python.3`), depois `pip install "graphifyy[mcp]"`. O `graphify` e o `graphify-mcp` ficam em `PythonXY\Scripts`, que só entra no PATH se o instalador do Python marcou "Add python.exe to PATH"; confira com `Get-Command graphify-mcp` (seção 4) | `apt install pipx`, depois `pipx install "graphifyy[mcp]"` e `pipx ensurepath`. Não use `pip` no Python do sistema: o Ubuntu 23.04+ e o Debian 12+ recusam com `externally-managed-environment` (PEP 668) | `brew install pipx`, depois `pipx install "graphifyy[mcp]"` e `pipx ensurepath` (o Python do Homebrew tem a mesma trava do PEP 668) |
| Claude Code e/ou Antigravity (Gemini) | instalados normalmente | instalados normalmente | instalados normalmente |

O pacote instala dois comandos: `graphify` (CLI e `graphify update .`) e `graphify-mcp` (o servidor MCP, que o `.mcp.json` chama). O `pipx` cria um ambiente isolado para o pacote e põe os dois em `~/.local/bin`, sem tocar no Python do sistema; o `pipx ensurepath` acrescenta essa pasta ao PATH (abra um terminal novo depois). Nenhum MCP deste template depende de `python` no PATH.

Depois de instalar o `pwsh`, todo comando deste README (`pwsh -NoProfile -File ...`) funciona igual nos três sistemas. Windows PowerShell 5.1 continua presente no Windows por padrão do sistema operacional; os scripts deste template continuam compatíveis com ele quando invocados manualmente por hábito antigo, mas o caminho oficial e testado é sempre `pwsh`.

Também é preciso de uma variável de ambiente de **usuário** `CONTEXT7_API_KEY` (chave do MCP `context7`). Nunca em arquivo versionado. No Windows, defina com `[Environment]::SetEnvironmentVariable(...)` (seção 4); no Linux/macOS, exporte no arquivo de perfil do seu shell (`~/.bashrc`, `~/.zshrc` ou equivalente): `export CONTEXT7_API_KEY="<sua-chave>"`, depois `source` o arquivo ou abra um terminal novo.

---

## 3. Criar um projeto a partir deste template

**Opção A — "Use this template" no GitHub** (recomendado, sem carregar o histórico de commits deste template):

1. Na página do repositório no GitHub, clique em **Use this template → Create a new repository**.
2. Escolha nome, visibilidade e crie o novo repositório.
3. Clone o repositório novo na sua máquina.

**Opção B — clonar diretamente:**

**Windows** (PowerShell):
```powershell
git clone <url-do-template> meu-novo-projeto
cd meu-novo-projeto
Remove-Item -Recurse -Force .git
git init -b main
```

**Linux/macOS** (bash/zsh):
```bash
git clone <url-do-template> meu-novo-projeto
cd meu-novo-projeto
rm -rf .git
git init -b main
```

Depois de criar o projeto, veja a seção 4 — **rodar o setup é o primeiro passo, sempre.**

O projeto novo herda este README. Reescreva-o para o seu projeto e apague a seção 10, que só serve para o repositório do template. O primeiro commit do projeto novo é o de sempre: `git add -A` e `git commit`.

---

## 4. Setup (primeiro passo em qualquer clone/PC)

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup-agents.ps1
```

(`-ExecutionPolicy Bypass` é aceito pelo `pwsh` nos três sistemas; fora do Windows ele é simplesmente ignorado, sem aviso.)

O que ele faz, sempre de forma idempotente (rodar de novo não duplica nada):

1. Cria o link `.claude/skills` → `.agents/skills`, para o Claude Code enxergar a skill `pre-pr`: uma **junction** no Windows (não precisa de admin) e um **symlink relativo** no Linux/macOS.
2. Regenera o comando do hook de formatação (`pwsh -EncodedCommand`, um base64 do conteúdo de `.agents/scripts/hook-launcher.ps1`) em `.claude/settings.json` e `.agents/hooks.json`. **Nunca edite esse base64 à mão** — mude `hook-launcher.ps1` e rode o setup de novo. Se o repositório ainda tiver o comando antigo `powershell ... -EncodedCommand` (de uma versão anterior deste template, só para Windows), o setup migra automaticamente para `pwsh ...` na mesma rodada.
3. Se o `graphify` estiver no PATH, instala a skill dele **globalmente para o seu usuário** com `graphify install --platform claude` e `graphify install --platform antigravity`. Esse passo grava **fora deste repositório**, em três destinos que valem para **todos os seus projetos**, a partir do `$HOME` do usuário atual (`$env:USERPROFILE` no Windows, `$HOME` no Linux/macOS):

   | Destino global | Gravado por | O que é |
   | --- | --- | --- |
   | `~/.claude/skills/graphify/` | `--platform claude` | a skill do graphify para o Claude Code |
   | `~/.claude/CLAUDE.md` | `--platform claude` | criado ou editado com uma seção `# graphify` que registra a skill; entra em **toda** sessão do Claude Code, em qualquer projeto |
   | `~/.gemini/config/skills/graphify/` | `--platform antigravity` | a skill do graphify para o Antigravity/Gemini |

   Se a variável `CLAUDE_CONFIG_DIR` estiver definida, os dois destinos do Claude Code ficam dentro dela no lugar de `~/.claude`. O setup imprime uma linha `GLOBAL: <caminho>` para cada destino, depois do `OK` ou do `WARN` de cada plataforma. Esses destinos não conflitam com o link `.claude/skills` deste projeto, que só expõe a skill `pre-pr`.

   Se o `graphify` não estiver no PATH, ou se o `graphify install` sair com código diferente de zero, o setup imprime um `WARN`. A saída do graphify, incluindo avisos em stderr, é descartada. Com exit 0 o passo conta como `OK`. Em todos os casos o setup termina com exit 0. Para instalar o graphify (detalhes na seção 2):

   **Windows:**
   ```powershell
   pip install "graphifyy[mcp]"
   Get-Command graphify, graphify-mcp
   ```
   O `pip` põe o `graphify.exe` e o `graphify-mcp.exe` na pasta `Scripts` do Python (ex.: `%LOCALAPPDATA%\Programs\Python\Python313\Scripts`). Ela só entra no PATH se o instalador do Python marcou **"Add python.exe to PATH"**. Se o `Get-Command` não achar os dois, acrescente essa pasta ao PATH do usuário e abra um terminal novo:
   ```powershell
   $scripts = python -c "import sysconfig; print(sysconfig.get_path('scripts'))"
   [Environment]::SetEnvironmentVariable('Path', [Environment]::GetEnvironmentVariable('Path', 'User') + ';' + $scripts, 'User')
   ```

   **Linux/macOS** (`apt install pipx` ou `brew install pipx` antes):
   ```bash
   pipx install "graphifyy[mcp]"
   pipx ensurepath
   ```
   **Para não gravar nada fora do repositório**, rode o setup com `-SkipGraphifyInstall`. Ele cria o link e sincroniza os hooks, imprime `SKIP: graphify install (-SkipGraphifyInstall)` e não chama o `graphify`:
   ```powershell
   pwsh -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup-agents.ps1 -SkipGraphifyInstall
   ```
   O `graphify install` não tem opção para instalar a skill global do Claude Code sem mexer em `~/.claude/CLAUDE.md` (conferido no `graphify install --help` e no código do instalador). A única alternativa dele é `--project`, que grava no repositório (`.claude/`, `CLAUDE.md` e `.agents/`), por cima dos arquivos deste template. Por isso o setup não usa `--project`. Se você não quer a seção global, use `-SkipGraphifyInstall` e remova a seção `# graphify` de `~/.claude/CLAUDE.md` se ela já existir.

Depois, defina a chave do MCP `context7`:

**Windows** (PowerShell, `pwsh` ou 5.1):
```powershell
[Environment]::SetEnvironmentVariable('CONTEXT7_API_KEY', '<sua-chave>', 'User')
```

**Linux** (bash, `~/.bashrc`):
```bash
echo 'export CONTEXT7_API_KEY="<sua-chave>"' >> ~/.bashrc
source ~/.bashrc
```

**macOS** (zsh, o shell padrão, `~/.zshrc`):
```bash
echo 'export CONTEXT7_API_KEY="<sua-chave>"' >> ~/.zshrc
source ~/.zshrc
```

**Feche e reabra o IDE por completo** (todas as janelas) depois de definir a variável — é a única forma de recarregar o PATH e a variável de ambiente em sessões já abertas. Se o Claude Code também rodar como extensão dentro de outro host (Antigravity IDE, VS Code, Cursor), reinicie esse host também.

Rode `graphify update .` na raiz para gerar `graphify-out/graph.json` na primeira vez. O `graphify-out/` é gerado localmente e não é versionado (está no `.gitignore`): cada clone gera o seu, e o grafo é regenerado com `graphify update .` depois de mudar código.

---

## 5. Declarar o primeiro subprojeto em `AGENTS.md`

Quando o projeto ganhar código executável (uma API, um frontend, um serviço), edite `AGENTS.md`:

1. **§1 — Mapeamento de Módulos**: acrescente uma linha na tabela com o diretório do novo subprojeto, a tecnologia e a função.
2. **§2 — Comandos Mecânicos**: acrescente um bloco `### <subprojeto>/` com os comandos reais de formatação, lint + tipos, testes + cobertura (≥ 80%), build e teste real em runtime (como subir o serviço, quais URLs checar, como encerrar). No Windows, escreva `curl.exe`: em Windows PowerShell 5.1 `curl` é alias de `Invoke-WebRequest` e não aceita as opções do curl (o `pwsh` não tem esse alias, mas o comando documentado deve funcionar em qualquer shell do Windows). No Linux/macOS, use `curl` normalmente.
3. **Frases de "sem subprojeto"**: apague as frases que só valem para o template recém-clonado. No §1, "Ao clonar este template, ainda não há nenhum subprojeto executável: a tabela lista só a infraestrutura de governança." No §2, "Ainda não há subprojeto executável." Em `.agents/rules/real-runtime-verification.md` §2.1, "Ao clonar este template, o §1 não lista nenhum."
4. **Skill `pre-pr`**: não precisa de ajuste. A skill `pre-pr` já lê os comandos do §2 do subprojeto afetado; não os copie para ela, para que o `AGENTS.md` continue sendo a fonte única.

A partir daí, todo o pipeline (seção 6) passa a rodar os gates desse subprojeto.

---

## 6. O pipeline de agentes e a política de veredito

Quatro papéis, cada um com definição única em `.agents/agents/`:

| Papel | Quando | Escreve código? |
| --- | --- | --- |
| `feature-implementer` | escopo definido, hora de codar (TDD, cobertura ≥ 80%) | sim |
| `code-reviewer` | implementação pronta, antes do PR | **não** — só relatório |
| `qa-validator` | review aprovado, antes de declarar pronto | não — só relatório |
| `bug-fixer` | bug, teste vermelho, achado de QA/review | sim |

**Fluxo padrão**: normalizar o pedido → `feature-implementer` → `code-reviewer` → `qa-validator` → (se achado bloqueante) `bug-fixer` → volta ao `code-reviewer` → decisão humana de commit/push/PR. Nenhum agente faz commit, push ou abre PR — isso é sempre humano.

**Política de veredito — proporcional**: só achado **bloqueante** (severidade Alta ou Média: defeito funcional, gate vermelho, segredo, instrução quebrada, critério de aceite sem teste) reprova (`REJECTED`) e volta para o `bug-fixer` e depois para uma nova revisão. Achados Baixos (redação, estilo, consistência de texto) saem como notas num `APPROVED`; o `bug-fixer` os corrige na mesma passada, se for barato, sem nova rodada. Mudança só de docs/regras/config tem um review e não passa pelo QA; pedido de dificuldade Baixa dispensa o registro em `docs/prompts/`. Detalhes em "Proporcionalidade", no `agent-pipeline.md`. Uma revisão que não pôde rodar (ex.: `claude` fora do PATH) é `NOT REVIEWED`, nunca uma aprovação.

Como invocar em cada ambiente, detalhes de separação de modelos (implementador ≠ revisor) e os formatos completos de relatório: [`.agents/rules/agent-pipeline.md`](.agents/rules/agent-pipeline.md).

---

## 7. Mapa de arquivos

```
.agents/
├── agents/       feature-implementer, code-reviewer, bug-fixer, qa-validator (fonte única dos papéis)
├── rules/        agent-pipeline, engineering-standards, graphify, mandatory-pre-pr,
│                 prompt-audit-breakdown, prompt-template, real-runtime-verification
├── skills/       pre-pr/ (a skill do graphify é instalada globalmente pelo setup, não vive aqui)
├── workflows/    implement, review, qa, bugfix, handoff, graphify (comandos do Antigravity)
├── scripts/      hook-launcher.ps1, post-tool-formatter.ps1, review-opus.ps1, setup-agents.ps1,
│                 tests/post-tool-formatter.cases.ps1 (rodam com pwsh nos três sistemas)
└── hooks.json    hook de formatação para o Antigravity
.claude/
├── agents/       wrappers que apontam para .agents/agents/
├── commands/     /implement /review /qa /bugfix /handoff
├── settings.json hook PostToolUse (Edit|Write) + permissões
└── skills        link -> .agents/skills (junction no Windows, symlink no Linux/macOS;
                  criado pelo setup-agents.ps1, ignorado pelo git)
docs/
├── prompts/      pedidos normalizados + quebra por dificuldade + handoff (.gitkeep)
├── reviews/      pareceres do code-reviewer (.gitkeep)
├── pre-pr/       relatórios pre-pr (.gitkeep)
└── qa/           relatórios de QA e bugs (.gitkeep)
graphify-out/     grafo local gerado por `graphify update .` (ignorado pelo git, não versionado)
.mcp.json         MCPs do Claude Code: context7, graphify, playwright
AGENTS.md         fonte única de governança
CLAUDE.md         ponteiro leve (@AGENTS.md) para o Claude Code
GEMINI.md         ponteiro leve para o Antigravity/Gemini
.gitignore .gitattributes
```

---

## 8. Exemplo de `mcp_config.json` do Antigravity

O Antigravity lê os MCPs em `~/.gemini/config/mcp_config.json` (`~\.gemini\config\mcp_config.json` no Windows). Esse arquivo é **global**: fica fora de qualquer repositório, é do seu usuário nesta máquina, vale para todos os projetos e **nunca** é versionado.

**Windows:**

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx.cmd",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "graphify": {
      "command": "graphify-mcp",
      "args": []
    }
  }
}
```

**Linux/macOS** (mesma estrutura; `npx` sem a extensão `.cmd`, que só existe no Windows; o `graphify-mcp` é o mesmo nos três sistemas). **Não verificado**: este bloco não foi testado no Antigravity em Linux nem em macOS:

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "graphify": {
      "command": "graphify-mcp",
      "args": []
    }
  }
}
```

**context7.** A chave não vai no arquivo, conforme a regra 6 do `AGENTS.md`: ela vem só da variável de ambiente de usuário `CONTEXT7_API_KEY` (seção 4). O exemplo usa só `npx(.cmd) -y @upstash/context7-mcp`, sem chave em `args` e sem bloco `env`. O pacote `@upstash/context7-mcp` (versão 4.1.1, conferida no código do pacote) lê `CONTEXT7_API_KEY` do ambiente sozinho. Não use `"env": {"CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}"}`: não há evidência de que o Antigravity expanda `${...}` nesse arquivo, e a string literal sobrescreveria a variável real.

> **Não verificado:** que o Antigravity repasse a variável de usuário ao processo do MCP. Se o context7 não autenticar só com a variável, não grave a chave em arquivo nenhum, nem neste arquivo global. O caminho é propor uma mudança da regra 6 pelo protocolo de melhoria contínua (regra 8 do `AGENTS.md`), com diff estruturado e aprovação humana.

O comando é `npx.cmd` no Windows (o nome do script do `npx` lá, como na configuração verificada) e `npx` nos demais sistemas. Diferente do `.mcp.json` do Claude Code (seção 7), aqui o Antigravity resolve o comando diretamente sem precisar de um wrapper de shell (`cmd` ou `pwsh`). No Windows, com `npx.cmd`, é a forma já verificada em uso; a forma de Linux/macOS não foi verificada.

**graphify.** Num arquivo global, o diretório de trabalho do MCP não é garantidamente a raiz do projeto, então não use caminho relativo para o grafo. O `graphify-mcp` é o entry point `graphify.serve:_main` do pacote, o mesmo código do `python -m graphify.serve`, com as mesmas opções. Há duas formas corretas, conferidas no `graphify-mcp --help` e no código do `graphify.serve`:

- **Sem grafo fixo (a do exemplo)**: sem grafo no diretório de trabalho, o servidor sobe em modo multiprojeto. Cada ferramenta recebe o parâmetro `project_path` com o caminho absoluto da raiz do projeto e lê `<project_path>/graphify-out/graph.json` (`\` no Windows). Uma chamada sem `project_path` recebe um erro claro.
- **Grafo fixo de um projeto**: `"args": ["--graph", "<caminho absoluto>/graphify-out/graph.json"]` (com `\\` no Windows). Serve só esse projeto.

**O que foi verificado e o que não foi:**

| Item | Situação |
| --- | --- |
| Estrutura `command`/`args` com `npx.cmd` e `-y @upstash/context7-mcp` para o context7, e o servidor do graphify sem grafo fixo | verificada: estrutura em uso num `mcp_config.json` global que funciona no Antigravity, com o graphify iniciado por `python -m graphify.serve`. Lá a chave do context7 vai em `--api-key` **e** num bloco `env` com valor literal, e não foi isolado qual dos dois autentica. As duas formas põem a chave no arquivo e por isso não são usadas neste exemplo (regra 6). A troca para `graphify-mcp` (mesmo `graphify.serve:_main`) não foi testada dentro do Antigravity; o handshake MCP `initialize` do `graphify-mcp` via stdio foi verificado no Windows e no Ubuntu |
| Leitura de `CONTEXT7_API_KEY` do ambiente pelo `@upstash/context7-mcp` 4.1.1 | verificada no código do pacote |
| Autenticação só via variável de ambiente, sem chave no arquivo | **não verificado** |
| Opções `--graph` e modo multiprojeto com `project_path` do `graphify.serve` | verificadas no `--help` e no código |
| O Antigravity repassar as variáveis de usuário ao processo do MCP, na forma do exemplo | **não verificado** |
| O Antigravity expandir `${VAR}` dentro do `mcp_config.json` | **não verificado**; por isso o exemplo não usa |

---

## 9. Problemas comuns

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `pwsh: command not found` / `'pwsh' não é reconhecido` | PowerShell 7 não instalado ou fora do PATH | Instale conforme a tabela da seção 2 e abra um terminal novo |
| `graphify` não é reconhecido depois de instalar | PATH desatualizado na sessão do IDE | Reabra o IDE por completo (todas as janelas) |
| MCP do graphify não sobe / `mcp not installed` | Faltou o extra `mcp` do pacote | Windows: `pip install "graphifyy[mcp]"`. Linux/macOS: `pipx install --force "graphifyy[mcp]"` |
| `error: externally-managed-environment` ao rodar `pip install` no Linux/macOS | O Python do sistema (Ubuntu 23.04+, Debian 12+, Homebrew) é gerenciado externamente (PEP 668) e o `pip` recusa instalar nele, inclusive com `--user` | Use o `pipx`: `apt install pipx` (ou `brew install pipx`), `pipx install "graphifyy[mcp]"` e `pipx ensurepath`. Não use `--break-system-packages` |
| `graphify-mcp: command not found` / `graphify: command not found` depois do `pipx install` | `~/.local/bin` ainda não está no PATH | `pipx ensurepath`, depois abra um terminal novo e reabra o IDE por completo |
| Hook de formatação quebra ou o PowerShell mostra caracteres corrompidos | Um `.ps1` foi salvo com acentos fora de ASCII | Scripts `.ps1` deste projeto são só ASCII — remova acentos e travessões |
| O hook parou de bater com `hook-launcher.ps1` | O base64 em `.claude/settings.json` / `.agents/hooks.json` foi editado à mão | Nunca edite o base64 — mude o launcher e rode `setup-agents.ps1` de novo |
| O hook ainda usa o comando antigo `powershell ... -EncodedCommand` | O setup deste template (versão com `pwsh`) ainda não rodou neste clone | Rode `setup-agents.ps1`; ele migra o comando automaticamente |
| `.claude/skills` não aparece ou aponta para o lugar errado | Setup não rodou, ou rodou antes de mudanças em `.agents/skills` | Rode `setup-agents.ps1`; ele recria o link (junction no Windows, symlink no Linux/macOS) se o alvo mudou |
| No Linux/macOS, `New-Item -ItemType SymbolicLink` falha com permissão negada | Sistema de arquivos ou política local bloqueia symlinks (raro fora de containers restritos) | Rode o setup com um usuário que tenha permissão de criar symlinks no diretório do projeto |
| Claude Code não pega a chave do `context7` | `CONTEXT7_API_KEY` foi definida depois que o IDE abriu, ou o `~/.bashrc`/`~/.zshrc` não foi recarregado | Reabra o IDE por completo depois de definir a variável de usuário |

---

## 10. Publicar este template (uma vez)

> Esta seção só vale para o repositório do template. Num projeto criado a partir dele, apague-a (seção 3).

Depois de ajustar o que quiser no template (ex.: `AGENTS.md` §1/§2 para a sua stack padrão), publique-o como um repositório privado no GitHub:

```powershell
git config user.name "<seu nome>"
git config user.email "<seu-email>"

git add -A
git commit -m "chore: template inicial de governanca de agentes de IA"
```

Crie o repositório **privado** pela interface web do GitHub (sem README, sem `.gitignore`, sem licença — este template já traz os seus), depois:

```powershell
git remote add origin <url-do-repositorio-privado>
git push -u origin main
```

Por fim, em **Settings → General** do repositório no GitHub, marque **Template repository**. A partir daí, qualquer projeto novo pode nascer com **Use this template**.

Ao criar um projeto a partir dele (seção 3), a primeira coisa a fazer é sempre rodar o setup (seção 4).
