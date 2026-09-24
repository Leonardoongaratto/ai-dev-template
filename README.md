# ai-dev-template

Template de repositório com uma governança de agentes de IA pronta para uso: papéis especializados (implementação, revisão, QA, correção de bugs), regras de engenharia, gates mecânicos obrigatórios (formatação, lint + tipos, testes com cobertura ≥ 80%, build, teste real em runtime), hooks de formatação automática e integração com os MCPs `context7` e `graphify`. Funciona com Claude Code e com Antigravity/Gemini no mesmo repositório, com uma única fonte de verdade (`AGENTS.md`).

Este template **não traz nenhum subprojeto**: ele é o esqueleto de governança que você aplica em cima de qualquer stack (Node, Python, Go, Rust, etc.), em um projeto único ou em um monorepo.

---

## 1. O que é

- **`AGENTS.md`**: fonte única de verdade para qualquer assistente de IA — mapeamento de módulos, comandos mecânicos obrigatórios, pipeline de agentes e regras invioláveis do repositório.
- **`CLAUDE.md` / `GEMINI.md`**: ponteiros leves que só importam `AGENTS.md`, para não duplicar regras e economizar tokens de contexto.
- **`.agents/`**: as definições que valem para qualquer ferramenta — regras (`rules/`), os quatro papéis (`agents/`), a skill `pre-pr` (`skills/pre-pr/`), os workflows do Antigravity (`workflows/`) e os scripts de automação (`scripts/`).
- **`.claude/`**: a integração específica do Claude Code — wrappers de subagentes (`agents/`), comandos de barra (`commands/`) e `settings.json` (hook de formatação + permissões). A pasta `.claude/skills` é uma junction para `.agents/skills`, criada pelo setup.
- **`docs/`**: histórico vivo e versionado de prompts, revisões, QA e relatórios Pre-PR (`prompts/`, `reviews/`, `pre-pr/`, `qa/`), cada um começando só com um `.gitkeep`.

---

## 2. Requisitos

- Windows com PowerShell 5.1 (os scripts de automação são `.ps1`).
- Git.
- Node.js, se algum subprojeto for JS/TS (necessário para o Prettier local que o hook de formatação usa).
- Python 3, para o `graphify` (`pip install "graphifyy[mcp]"` — o extra `mcp` é obrigatório para o servidor MCP).
- Claude Code e/ou Antigravity (Gemini) instalados.
- Uma variável de ambiente de **usuário** `CONTEXT7_API_KEY` (chave do MCP `context7`). Nunca em arquivo versionado.

---

## 3. Criar um projeto a partir deste template

**Opção A — "Use this template" no GitHub** (recomendado, sem carregar o histórico de commits deste template):

1. Na página do repositório no GitHub, clique em **Use this template → Create a new repository**.
2. Escolha nome, visibilidade e crie o novo repositório.
3. Clone o repositório novo na sua máquina.

**Opção B — clonar diretamente:**

```powershell
git clone <url-do-template> meu-novo-projeto
cd meu-novo-projeto
Remove-Item -Recurse -Force .git
git init -b main
```

Depois de criar o projeto, veja a seção 4 — **rodar o setup é o primeiro passo, sempre.**

O projeto novo herda este README. Reescreva-o para o seu projeto e apague a seção 10, que só serve para o repositório do template. O primeiro commit do projeto novo é o de sempre: `git add -A` e `git commit`.

---

## 4. Setup (primeiro passo em qualquer clone/PC)

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup-agents.ps1
```

O que ele faz, sempre de forma idempotente (rodar de novo não duplica nada):

1. Cria a junction `.claude\skills` → `.agents\skills`, para o Claude Code enxergar a skill `pre-pr`.
2. Regenera o comando do hook de formatação (`-EncodedCommand`, um base64 do conteúdo de `.agents/scripts/hook-launcher.ps1`) em `.claude\settings.json` e `.agents\hooks.json`. **Nunca edite esse base64 à mão** — mude `hook-launcher.ps1` e rode o setup de novo.
3. Se o `graphify` estiver no PATH, instala a skill dele **globalmente para o seu usuário** com `graphify install --platform claude` e `graphify install --platform antigravity`. Esse passo grava **fora deste repositório**, em três destinos que valem para **todos os seus projetos**:

   | Destino global | Gravado por | O que é |
   | --- | --- | --- |
   | `~\.claude\skills\graphify\` | `--platform claude` | a skill do graphify para o Claude Code |
   | `~\.claude\CLAUDE.md` | `--platform claude` | criado ou editado com uma seção `# graphify` que registra a skill; entra em **toda** sessão do Claude Code, em qualquer projeto |
   | `~\.gemini\config\skills\graphify\` | `--platform antigravity` | a skill do graphify para o Antigravity/Gemini |

   Se a variável `CLAUDE_CONFIG_DIR` estiver definida, os dois destinos do Claude Code ficam dentro dela no lugar de `~\.claude`. O setup imprime uma linha `GLOBAL: <caminho>` para cada destino, depois do `OK` ou do `WARN` de cada plataforma. Esses destinos não conflitam com a junction `.claude\skills` deste projeto, que só expõe a skill `pre-pr`.

   Se o `graphify` não estiver no PATH, ou se o `graphify install` sair com código diferente de zero, o setup imprime um `WARN`. A saída do graphify, incluindo avisos em stderr, é descartada. Com exit 0 o passo conta como `OK`. Em todos os casos o setup termina com exit 0. Para instalar o graphify:
   ```powershell
   python -m pip install "graphifyy[mcp]"
   ```
   **Para não gravar nada fora do repositório**, rode o setup com `-SkipGraphifyInstall`. Ele cria a junction e sincroniza os hooks, imprime `SKIP: graphify install (-SkipGraphifyInstall)` e não chama o `graphify`:
   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup-agents.ps1 -SkipGraphifyInstall
   ```
   O `graphify install` não tem opção para instalar a skill global do Claude Code sem mexer em `~\.claude\CLAUDE.md` (conferido no `graphify install --help` e no código do instalador). A única alternativa dele é `--project`, que grava no repositório (`.claude\`, `CLAUDE.md` e `.agents\`), por cima dos arquivos deste template. Por isso o setup não usa `--project`. Se você não quer a seção global, use `-SkipGraphifyInstall` e remova a seção `# graphify` de `~\.claude\CLAUDE.md` se ela já existir.

Depois:

```powershell
[Environment]::SetEnvironmentVariable('CONTEXT7_API_KEY', '<sua-chave>', 'User')
```

**Feche e reabra o IDE por completo** (todas as janelas) depois de definir a variável — é a única forma de recarregar o PATH e a variável de ambiente em sessões já abertas. Se o Claude Code também rodar como extensão dentro de outro host (Antigravity IDE, VS Code, Cursor), reinicie esse host também.

Rode `graphify update .` na raiz para gerar `graphify-out/graph.json` na primeira vez. O `graphify-out/` é gerado localmente e não é versionado (está no `.gitignore`): cada clone gera o seu, e o grafo é regenerado com `graphify update .` depois de mudar código.

---

## 5. Declarar o primeiro subprojeto em `AGENTS.md`

Quando o projeto ganhar código executável (uma API, um frontend, um serviço), edite `AGENTS.md`:

1. **§1 — Mapeamento de Módulos**: acrescente uma linha na tabela com o diretório do novo subprojeto, a tecnologia e a função.
2. **§2 — Comandos Mecânicos**: acrescente um bloco `### <subprojeto>/` com os comandos reais de formatação, lint + tipos, testes + cobertura (≥ 80%), build e teste real em runtime (como subir o serviço, quais URLs checar com `curl.exe`, como encerrar). No PowerShell 5.1, `curl` é alias de `Invoke-WebRequest` e não aceita as opções do curl; escreva `curl.exe`.
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
│                 tests/post-tool-formatter.cases.ps1
└── hooks.json    hook de formatação para o Antigravity
.claude/
├── agents/       wrappers que apontam para .agents/agents/
├── commands/     /implement /review /qa /bugfix /handoff
├── settings.json hook PostToolUse (Edit|Write) + permissões
└── skills        junction -> .agents/skills (criada pelo setup-agents.ps1, ignorada pelo git)
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

O Antigravity lê os MCPs em `~\.gemini\config\mcp_config.json`. Esse arquivo é **global**: fica fora de qualquer repositório, é do seu usuário nesta máquina, vale para todos os projetos e **nunca** é versionado.

```json
{
  "mcpServers": {
    "context7": {
      "command": "npx.cmd",
      "args": ["-y", "@upstash/context7-mcp"]
    },
    "graphify": {
      "command": "python",
      "args": ["-m", "graphify.serve"]
    }
  }
}
```

**context7.** A chave não vai no arquivo, conforme a regra 6 do `AGENTS.md`: ela vem só da variável de ambiente de usuário `CONTEXT7_API_KEY` (seção 4). O exemplo usa só `npx.cmd -y @upstash/context7-mcp`, sem chave em `args` e sem bloco `env`. O pacote `@upstash/context7-mcp` (versão 4.1.1, conferida no código do pacote) lê `CONTEXT7_API_KEY` do ambiente sozinho. Não use `"env": {"CONTEXT7_API_KEY": "${CONTEXT7_API_KEY}"}`: não há evidência de que o Antigravity expanda `${...}` nesse arquivo, e a string literal sobrescreveria a variável real.

> **Não verificado:** que o Antigravity repasse a variável de usuário ao processo do MCP. Se o context7 não autenticar só com a variável, não grave a chave em arquivo nenhum, nem neste arquivo global. O caminho é propor uma mudança da regra 6 pelo protocolo de melhoria contínua (regra 8 do `AGENTS.md`), com diff estruturado e aprovação humana.

O comando é `npx.cmd`, o nome do script do `npx` no Windows, como na configuração verificada.

**graphify.** Num arquivo global, o diretório de trabalho do MCP não é garantidamente a raiz do projeto, então não use caminho relativo para o grafo. Há duas formas corretas, conferidas no `python -m graphify.serve --help` e no código do `graphify.serve`:

- **Sem grafo fixo (a do exemplo)**: sem grafo no diretório de trabalho, o servidor sobe em modo multiprojeto. Cada ferramenta recebe o parâmetro `project_path` com o caminho absoluto da raiz do projeto e lê `<project_path>\graphify-out\graph.json`. Uma chamada sem `project_path` recebe um erro claro.
- **Grafo fixo de um projeto**: `"args": ["-m", "graphify.serve", "--graph", "<caminho absoluto>\\graphify-out\\graph.json"]`. Serve só esse projeto.

**O que foi verificado e o que não foi:**

| Item | Situação |
| --- | --- |
| Estrutura `command`/`args` com `npx.cmd` e `-y @upstash/context7-mcp` para o context7, e `python -m graphify.serve` sem grafo fixo para o graphify | verificada: estrutura em uso num `mcp_config.json` global que funciona no Antigravity. Lá a chave do context7 vai em `--api-key` **e** num bloco `env` com valor literal, e não foi isolado qual dos dois autentica. As duas formas põem a chave no arquivo e por isso não são usadas neste exemplo (regra 6) |
| Leitura de `CONTEXT7_API_KEY` do ambiente pelo `@upstash/context7-mcp` 4.1.1 | verificada no código do pacote |
| Autenticação só via variável de ambiente, sem chave no arquivo | **não verificado** |
| Opções `--graph` e modo multiprojeto com `project_path` do `graphify.serve` | verificadas no `--help` e no código |
| O Antigravity repassar as variáveis de usuário ao processo do MCP, na forma do exemplo | **não verificado** |
| O Antigravity expandir `${VAR}` dentro do `mcp_config.json` | **não verificado**; por isso o exemplo não usa |

---

## 9. Problemas comuns

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `graphify` não é reconhecido depois de instalar | PATH desatualizado na sessão do IDE | Reabra o IDE por completo (todas as janelas) |
| MCP do graphify não sobe / `mcp not installed` | Faltou o extra `mcp` do pacote | `pip install "graphifyy[mcp]"` |
| Hook de formatação quebra ou o PowerShell mostra caracteres corrompidos | Um `.ps1` foi salvo com acentos fora de ASCII | Scripts `.ps1` deste projeto são só ASCII — remova acentos e travessões |
| O hook parou de bater com `hook-launcher.ps1` | O base64 em `.claude\settings.json` / `.agents\hooks.json` foi editado à mão | Nunca edite o base64 — mude o launcher e rode `setup-agents.ps1` de novo |
| `.claude\skills` não aparece ou aponta para o lugar errado | Setup não rodou, ou rodou antes de mudanças em `.agents\skills` | Rode `setup-agents.ps1`; ele recria a junction se o alvo mudou |
| Claude Code não pega a chave do `context7` | `CONTEXT7_API_KEY` foi definida depois que o IDE abriu | Reabra o IDE por completo depois de definir a variável de usuário |

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
