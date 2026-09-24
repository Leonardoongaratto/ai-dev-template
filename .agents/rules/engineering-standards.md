---
trigger: always_on
description: Regras de engenharia invioláveis do projeto (Clean Code, cobertura >= 80%, context7, graphify, pipeline de agentes, pre-pr, runtime, encoding no Windows).
---

# Padrões de Engenharia e Regras Operacionais

Este documento define regras de engenharia invioláveis e fluxos de trabalho obrigatórios para todos os agentes autônomos.

---

## 1. Consulta ao MCP Context7 (Documentação Técnica)
- Toda vez que executar uma tarefa que envolva bibliotecas externas ou frameworks, consulte o MCP **`context7`** (`resolve-library-id` e `query-docs`) sempre que necessário para verificar assinaturas corretas, métodos atualizados e melhores práticas vigentes da versão das bibliotecas.

---

## 2. Padrões de Clean Code e Alta Performance
- **Clean Code**: Funções com responsabilidade única (SRP), nomes claros e autoexplicativos em inglês, tipagem estrita, sem código morto e sem comentários redundantes.
- **Máxima Performance**: Connection pooling para HTTP, banco e mensageria, prepared statements no ORM, pré-alocação de memória para coleções conhecidas e isolamento de locks/mutexes de I/O de rede.
- **Resiliência e Defensive Coding**: Tratamento explícito de exceções e erros, timeouts obrigatórios em chamadas HTTP/gRPC e contingência elegante para falhas externas.

---

## 3. Cobertura Mínima de Testes (≥ 80%)
- **Mandatório**: Todo projeto deve manter no mínimo **80% de cobertura de testes**.
- Cada `<acceptance_criteria>` especificado no prompt deve ser transformado em casos de teste automatizados correspondentes.
- PRs, commits ou implementações que rebaixem a cobertura global abaixo de 80% são sumariamente rejeitados.

---

## 4. Atualização Obrigatória do Grafo de Conhecimento (Graphify)
- Ao final de qualquer etapa que alterou o código-fonte (`feature-implementer`, `bug-fixer`), **SEMPRE** execute:
  ```bash
  graphify update .
  ```
  Isso garante que o grafo de conhecimento semântico e estrutural (`graphify-out/`, local e não versionado) permaneça sincronizado.

---

## 5. Uso Obrigatório do Pipeline de Agentes Especializados (`.agents/agents/`)
- É **mandatório** utilizar as personas especializadas de `.agents/agents/` em cada fase do ciclo de desenvolvimento:
  - **`feature-implementer`**: Desenvolvimento guiado por TDD com cobertura $\ge 80\%$ e Clean Code.
  - **`bug-fixer`**: Resolução de defeitos com reprodução obrigatória via teste falho (Red) antes da correção (Green).
  - **`code-reviewer`**: Auditoria mecânica independente (comandos do bloco `### <subprojeto>/` do `AGENTS.md` §2: formatação, lint + tipos, testes com cobertura $\ge 80\%$, build) e parecer formal em `docs/reviews/`.
  - **`qa-validator`**: Validação operacional em runtime, injeção de prompt adversário, mascaramento de PII e observabilidade.
- Fluxo, roteamento, invocação em cada ambiente e formatos de relatório: [`.agents/rules/agent-pipeline.md`](agent-pipeline.md).

---

## 6. Proibição de Comentários Desnecessários e Remoção Compulsória
- **Não adicionar comentários desnecessários**: O código deve ser limpo, expressivo e autoexplicativo por meio de sua nomenclatura, tipagem e arquitetura. É expressamente proibido adicionar comentários redundantes ou óbvios que apenas narram o que a instrução de código já expressa.
- **Remoção compulsória de comentários desnecessários**: Ao inspecionar, refatorar ou modificar qualquer arquivo, todo comentário narrativo, óbvio ou bloco de código comentado (código morto) encontrado **DEVE ser sumariamente removido**.
- **Única exceção aceita**: Comentários são permitidos exclusivamente para documentar o *porquê* de decisões arquiteturais complexas ou advertências de segurança crítica.

---

## 7. Uso Obrigatório e Evidenciação da Skill `pre-pr` ao Final de Toda Implementação
- **Mandatório ao final de qualquer tarefa de código**: Ao concluir qualquer implementação, refatoração ou correção de bug, é **estritamente obrigatório** executar os gates da skill **`pre-pr`**.
- O agente deve salvar uma cópia em `docs/pre-pr/<YYYY-MM-DD_HH-mm>_<task>-pre-pr.md` e exibir no fechamento da resposta final o **Relatório Pre-PR Estruturado** com evidências frescas de execução dos comandos.

---

## 8. Execução Obrigatória do Projeto e Verificação em Teste Real ao Final de Cada Execução
- **Mandatório ao final de qualquer ciclo de desenvolvimento**: Ao concluir qualquer implementação de funcionalidade, refatoração estrutural ou correção de bug, é **estritamente obrigatório rodar o projeto e verificar o funcionamento em teste real**, conforme definido em [`.agents/rules/real-runtime-verification.md`](real-runtime-verification.md) (inclusive a isenção para mudanças sem código executável).
- O agente deve iniciar o serviço, disparar requisições reais via `curl.exe` (no PowerShell 5.1, `curl` é alias de `Invoke-WebRequest`) contra `/health` e rotas alteradas, validar resposta HTTP 200 e encerrar o processo de forma limpa.

---

## 9. Protocolo de Melhoria Contínua ("Knowledge Suggestion")
- **Gatilho**: Sempre que o agente enfrentar dificuldade, erro inesperado de biblioteca, ambiguidade de padrão ou falha decorrente de regra omissa ou skill desatualizada.
- **Resolução Prévia**: O agente resolve o código e garante testes passando (Green).
- **Proposta Estruturada**: Inclui compulsoriamente no fechamento um bloco com diff da melhoria proposta para aprovação humana:
  ```markdown
  > [!TIP]
  > ### Proposta de Atualização de Governança
  > - **Problema Identificado**: <descrição concisa do erro ou gargalo>
  > - **Causa Raiz**: <por que a IA ou o código falhou>
  > - **Arquivo a Alterar**: `.agents/skills/<nome>/SKILL.md` ou `.agents/rules/<nome>.md`
  > - **Modificação Proposta**: <diff>
  > - **Impacto Esperado**: Previne que agentes futuros cometam o mesmo erro.
  ```
- **Garantia de Segurança**: A IA nunca altera arquivos em `.agents/rules/` ou `.agents/skills/` compulsoriamente ou de forma silenciosa.

---

## 10. Encoding de Arquivos no Windows PowerShell 5.1
- **Scripts `.ps1`**: escreva só em ASCII ou em UTF-8 **com BOM**. O PowerShell 5.1 lê `.ps1` sem BOM na codepage ANSI do sistema, e acentos ou travessões (`—`) viram caracteres corrompidos ou quebram o parser.
- **Ler arquivos UTF-8**: use sempre `Get-Content <arquivo> -Encoding UTF8` (ou `-Raw -Encoding UTF8`). Sem o parâmetro, o 5.1 decodifica na codepage ANSI.
- **Gravar arquivos lidos por outras ferramentas**: passe `-Encoding utf8` explicitamente em `Set-Content`, `Add-Content` e `Out-File`; `Set-Content` sem o parâmetro grava em ANSI.
- **JSON e Markdown do repositório** continuam UTF-8 (sem BOM); a regra de BOM vale só para `.ps1` que contenha caracteres não ASCII.
