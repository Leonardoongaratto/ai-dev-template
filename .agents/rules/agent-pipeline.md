---
trigger: always_on
title: Pipeline de Agentes do Projeto
description: Regra do projeto para os agentes de implementação, revisão, QA e correção. Vale para qualquer assistente (Claude Code, Antigravity/Gemini ou outro) em qualquer subprojeto deste repositório.
---

# Pipeline de Agentes — regra do projeto

Vale para **todo** assistente que toca este projeto (Claude Code na extensão do VS Code, Antigravity/Gemini ou qualquer outro) e para todo subprojeto dentro dele, listado ou não em `AGENTS.md` §1. Não é um fluxo sugerido: é o caminho padrão para qualquer mudança de comportamento.

**Padrão, não opção.** O papel certo é escolhido pelo roteamento abaixo, sem perguntar se o pipeline deve ser usado. Pular uma etapa é decisão do usuário, dita por ele — nunca iniciativa do agente.

| O pedido chega como | Papel |
| --- | --- |
| feature, mudança de comportamento, novo módulo ou subprojeto | `feature-implementer` (depois de normalizar no template e aprovar o plano) |
| "revise", fim de implementação, antes do PR | `code-reviewer` |
| "teste", "valide", antes de declarar pronto | `qa-validator` |
| bug, crash, teste vermelho, achado de QA ou de review | `bug-fixer` |
| pergunta sobre o código, leitura de arquivo, comando único | nenhum — responder direto, sem cerimônia |

## Os quatro papéis

A definição de cada papel vive em **um único arquivo**, em `.agents/agents/`. Os wrappers de `.claude/agents/` e os workflows de `.agents/workflows/` só apontam para ele.

| Agente | Modelo | Definição | Quando | Escreve código? |
| --- | --- | --- | --- | --- |
| `feature-implementer` | `sonnet` no Claude Code; o da sessão (Gemini) no Antigravity | `.agents/agents/feature-implementer.md` | escopo definido, hora de codar | sim |
| `code-reviewer` | `opus`, sempre | `.agents/agents/code-reviewer.md` | implementação pronta, antes do PR | **não** |
| `qa-validator` | padrão | `.agents/agents/qa-validator.md` | review aprovado, antes de declarar pronto | não (só relatório) |
| `bug-fixer` | padrão | `.agents/agents/bug-fixer.md` | bug, teste vermelho, achado de QA/review | sim |

## Como invocar em cada ambiente

| Ambiente | Como |
| --- | --- |
| Claude Code (VS Code) | subagente pelo nome (`use o agente code-reviewer`) ou `/implement`, `/review`, `/qa`, `/bugfix`, `/handoff` (`.claude/commands/`). Os subagentes estão em `.claude/agents/` |
| Antigravity / Gemini | `/implement`, `/review`, `/qa`, `/bugfix`, `/handoff` (`.agents/workflows/`) — carregam os mesmos arquivos de `.agents/agents/` e `.agents/rules/` |
| Qualquer outro | abrir `.agents/agents/<papel>.md` e seguir; é markdown puro |

Um comando é só um gatilho. Para mudar comportamento, edite a definição em `.agents/agents/`, nunca o wrapper nem o workflow.

## Fluxo padrão

```
pedido (livre ou já no template)
   │
   ├─ 1. normalizar em .agents/rules/prompt-template.md      sessão principal
   ├─ 2. auditar e quebrar por dificuldade                    sessão principal · aprovação humana
   │      → docs/prompts/<YYYY-MM-DD_HH-mm>_<slug>.md
   │
   ├─ 3. feature-implementer  →  código + testes (TDD) + pre-pr
   │                              → docs/pre-pr/<YYYY-MM-DD_HH-mm>_<slug>-pre-pr.md
   ├─ 4. code-reviewer        →  docs/reviews/<YYYY-MM-DD>_<slug>-review.md
   ├─ 5. qa-validator         →  docs/qa/<YYYY-MM-DD>_<slug>-qa.md  (+ docs/qa/<slug>/bugs.md se falhar)
   ├─ 6. bug-fixer            →  correção + teste de regressão  ──┐
   │                                                              └─► volta ao passo 4 só se o achado era bloqueante
   └─ 7. decisão final        →  humano decide commit / push / PR
```

Os passos 1 e 2 são da sessão principal com o humano — agente não decide escopo. O passo 7 é humano — **nenhum agente faz commit, push de branch ou abre PR**.

A sessão principal dispara os passos 4 e 5 sozinha ao fim do passo 3, sem esperar pedido. No Claude Code isso conta como pedido explícito de subagentes.

## Proporcionalidade

A cerimônia acompanha o tamanho e o risco da mudança. O objetivo é pegar defeito real, não polir texto em rodadas sem fim.

- **Achado bloqueante** (severidade Alta ou Média): defeito funcional, gate vermelho, segredo ou falha de segurança, instrução que quebra o uso, critério de aceite sem teste. Reprova a revisão e volta ao `code-reviewer` depois do `bug-fixer`.
- **Achado não bloqueante** (severidade Baixa): redação, consistência de texto, estilo, sugestão. Não reprova: a revisão sai `APPROVED` com notas. O `bug-fixer` corrige na mesma passada, se for barato, **sem nova rodada de revisão**; senão fica registrado para depois.
- **Mudança só de docs, regras ou config de agentes:** um review, sem QA (não há o que rodar), e os gates que existirem (ex.: a suíte do hook) continuam obrigatórios.
- **Pedido de dificuldade Baixa** (`prompt-audit-breakdown.md`): dispensa o registro em `docs/prompts/`; a normalização pode ficar só na conversa.
- **QA** roda quando há código executável alterado; sem isso, é N/A.

## Por que subagentes e não um prompt gigante

Cada agente roda em contexto isolado: a sessão principal recebe o veredito, não as milhares de linhas de diff que ele leu. Isso mantém a sessão navegável e impede que o ruído de uma etapa contamine a seguinte.

O `code-reviewer` roda **sem acesso de edição ao código de produção**, de propósito. Um revisor que pode corrigir acaba aprovando a própria correção. No Claude Code o wrapper dele não tem a ferramenta `Edit`; `Write` fica liberada só para gravar o relatório em `docs/reviews/` e os achados em `docs/qa/<slug>/bugs.md`. No Antigravity o `review-opus.ps1` roda o revisor somente leitura: o script grava a resposta dele em `docs/reviews/`, e a sessão que chamou o script grava os achados no `bugs.md`.

### Separação de modelos e handoff automático

A intenção: quem implementa não é quem revisa. Dois modelos significam dois conjuntos de pontos cegos — o revisor não herda as suposições do implementador.

Um subagente do Claude Code só resolve modelos Anthropic (`opus`, `sonnet`, `haiku`, `fable`, `inherit` ou um id `claude-*`), nunca um Gemini. Por isso cada ambiente entrega a separação de um jeito:

| Rodando em | Implementador | Revisor |
| --- | --- | --- |
| Antigravity / Gemini | `/implement` no modelo Gemini da sessão | `/review` → `.agents/scripts/review-opus.ps1`, que chama o Claude headless com `.agents/agents/code-reviewer.md` em `opus` |
| Claude Code | subagente `feature-implementer`, fixo em `model: sonnet` | subagente `code-reviewer`, fixo em `model: opus`, sem `Edit` |

**Handoff automático**: com todos os gates verdes, o implementador entrega sozinho — subagente no Claude Code, `review-opus.ps1` no Antigravity. O relatório vai para `docs/reviews/`. Uma revisão que não pôde rodar (por exemplo, `claude` fora do PATH) é reportada como `NOT REVIEWED`, **nunca** como aprovação. Nesse caso, o fallback aceito é o `/review` do próprio Antigravity, registrado no relatório como "mesmo modelo do implementador".

## Agentes referenciam, não duplicam

O "como" vive nas skills (`.agents/skills/`) e nas regras (`.agents/rules/`). O agente decide *quando* e *contra quais critérios de aceite*. Quando um procedimento muda, atualize a skill ou a regra — não copie o texto para dentro do agente, ou as duas fontes divergem na primeira mudança.

| Necessidade | Onde está |
| --- | --- |
| formatação + lint + tipos + testes + cobertura + build + runtime + relatório | skill `pre-pr` · regra `mandatory-pre-pr.md` |
| subir o projeto e testar com requisição real | regra `real-runtime-verification.md` |
| normalizar o pedido | regra `prompt-template.md` |
| quebra por dificuldade e registro/handoff | regra `prompt-audit-breakdown.md` |
| Clean Code, sem comentários, cobertura, context7, graphify | regra `engineering-standards.md` |
| mapa do código | regra `graphify.md` (skill instalada globalmente pelo setup) |
| documentação de biblioteca | MCP `context7` |

## Regras que valem para os quatro

1. **Evidência fresca.** Comando não rodado nesta sessão não prova nada. Os gates rodam **dentro do subprojeto afetado** (ex.: `cd <subprojeto>`), com os comandos do bloco `### <subprojeto>/` do `AGENTS.md` §2. Confira o exit code, não a ausência de output.
2. **Nunca suprimir.** `eslint-disable`, `@ts-ignore`, `@ts-expect-error`, `# noqa`, `//nolint`, `.skip`, `.only`, `.todo`, threshold de cobertura rebaixado — proibidos. Corrija o código.
3. **Escopo é o diff.** Achado bloqueante dentro do diff reprova; achado Baixo e erro fora do diff viram nota no relatório, e a contagem global de erros não pode subir.
4. **Cobertura ≥ 80%** no subprojeto alterado, e cada `<acceptance_criteria>` tem um teste dedicado.
5. **Teste real em runtime.** Teste unitário verde não prova sistema rodando: subir o serviço (API: `/health` + rotas alteradas; frontend: `vite preview`/`dev` + `curl.exe` na página, esperando `200`), coletar a evidência e encerrar o processo. Exigido só quando há mudança de código em subprojeto executável; mudança só de docs, regras ou config de agentes registra "N/A — sem mudança de código executável" (`real-runtime-verification.md` §2.1).
6. **Sem browser/dispositivo, sem validação visual.** Diga que não validou visualmente; não deduza a UI a partir do código.
7. **Relatórios curtos e verificáveis**, com caminho e linha. Todo achado vem com proposta de correção.
8. **`graphify update .`** ao fim de qualquer etapa que alterou código.
9. **Handoff antes de perder o fôlego.** Ao terminar a etapa, o arquivo do pedido em `docs/prompts/` é atualizado (seções 3, 4 e 5 do template de `prompt-audit-breakdown.md`) — é o checkpoint entre etapas e entre ambientes. O `feature-implementer` e o `bug-fixer` atualizam o arquivo eles mesmos. O `code-reviewer` e o `qa-validator` não gravam em `docs/prompts/`: devolvem o veredito e o caminho do relatório, e a sessão principal registra no arquivo do pedido. Contexto ou cota perto do limite, aviso de compactação, ou bloqueio que não se resolve nesta sessão: pare o passo em andamento e escreva o handoff antes (o revisor e o QA, no próprio relatório). Trabalho interrompido sem handoff é trabalho perdido.

## Onde fica cada coisa

Neste projeto `docs/` **é versionado** (pastas com `.gitkeep`): relatórios servem de histórico vivo e de handoff entre Claude Code e Antigravity.

| Artefato | Onde | Produzido por |
| --- | --- | --- |
| Regra do pipeline | `.agents/rules/agent-pipeline.md` | — |
| Definição dos papéis (fonte única) | `.agents/agents/*.md` | — |
| Wrappers de subagente do Claude Code | `.claude/agents/*.md` | — |
| Comandos do Claude Code | `.claude/commands/*.md` | — |
| Workflows do Antigravity | `.agents/workflows/*.md` | — |
| Revisão cruzada a partir do Antigravity | `.agents/scripts/review-opus.ps1` | — |
| Pedido normalizado + tarefas + handoff | `docs/prompts/<YYYY-MM-DD_HH-mm>_<slug>.md` | sessão principal (que também registra os vereditos de review e de QA), atualizado pelo `feature-implementer` e pelo `bug-fixer` |
| Relatório Pre-PR | `docs/pre-pr/<YYYY-MM-DD_HH-mm>_<slug>-pre-pr.md` | `feature-implementer`, `bug-fixer` |
| Relatório de review | `docs/reviews/<YYYY-MM-DD>_<slug>-review.md` | `code-reviewer` no Claude Code; no Antigravity, o `review-opus.ps1` grava a resposta do revisor |
| Relatório de QA | `docs/qa/<YYYY-MM-DD>_<slug>-qa.md` | `qa-validator` |
| Bugs da feature | `docs/qa/<slug>/bugs.md` | `qa-validator`, `code-reviewer` (no Antigravity, a sessão que chamou o `review-opus.ps1`); `bug-fixer` acrescenta Status, Causa raiz, Correção e Testes de regressão |
| Evidências (screenshots, logs) | `docs/qa/evidence/` | `qa-validator`, `bug-fixer` |

## Formato do `bugs.md`

```
## BUG-01 — <título curto>
- **Severidade:** Alta | Média | Baixa
- **Subprojeto / arquivo:** <subprojeto> · <caminho/arquivo>:<linha>
- **Repro:** 1. ... 2. ... 3. ...
- **Esperado:** ...
- **Atual:** ...
- **Evidência:** docs/qa/evidence/<slug>-BUG-01.png | trecho de log/curl
```

Depois da correção, o `bug-fixer` acrescenta na mesma entrada: `Status`, `Causa raiz`, `Correção`, `Testes de regressão`.

## Formatos de relatório

**Review** — `docs/reviews/<YYYY-MM-DD>_<slug>-review.md`: veredito (APPROVED / REJECTED / NOT REVIEWED — só achado bloqueante, Alta ou Média, no diff reprova; achados Baixos saem como notas num APPROVED, ver "Proporcionalidade"), modelo que revisou, gates (formatação · lint + tipos · testes · cobertura · build · runtime), tabela de achados (`severidade | arquivo:linha | problema | correção sugerida`), tabela critério de aceite × teste, pontos positivos, recomendações.

**QA** — `docs/qa/<YYYY-MM-DD>_<slug>-qa.md`: status (APPROVED / REJECTED / PARTIAL — sem validação visual), ambiente usado (comando, porta, browser se houver), suítes rodadas, tabela `AC-xx | critério | PASS/FAIL | evidência`, estados verificados (loading, erro, vazio, sucesso), checklist de acessibilidade, segurança (segredos, PII, entradas adversárias), trechos de log, bugs encontrados.

## Precedência

`AGENTS.md` (e os ponteiros `CLAUDE.md` / `GEMINI.md`) > `.agents/rules/` > `.agents/agents/` > skills externas. Uma skill de fora não conhece as regras deste projeto; em conflito, o projeto vence.
