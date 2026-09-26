---
trigger: always_on
description: Regras de engenharia invioláveis do projeto (Clean Code, cobertura >= 80%, context7, graphify, pipeline de agentes, pre-pr, runtime, encoding no Windows).
---

# Padrões de Engenharia e Regras Operacionais

Regras de engenharia que valem para todos os agentes deste projeto.

---

## 1. Consulta ao MCP Context7 (Documentação Técnica)
- Ao usar API de biblioteca ou framework externo, confirme assinaturas e comportamento na documentação da versão em uso (MCP `context7`) em vez de confiar na memória.

---

## 2. Padrões de Clean Code e Alta Performance
- **Clean Code**: Funções com responsabilidade única (SRP), nomes claros e autoexplicativos em inglês, tipagem estrita, sem código morto e sem comentários redundantes.
- **Performance**: reutilize conexões (pool ou sessão) em vez de abrir uma por chamada e não faça I/O de rede segurando lock.
- **Resiliência e Defensive Coding**: Tratamento explícito de exceções e erros, timeouts obrigatórios em chamadas HTTP/gRPC e contingência elegante para falhas externas.

---

## 3. Cobertura Mínima de Testes (≥ 80%)
- Todo subprojeto mantém no mínimo 80% de cobertura de testes.
- Cada `<acceptance_criteria>` especificado no prompt deve ser transformado em casos de teste automatizados correspondentes.
- Mudança que deixe a cobertura abaixo de 80% é achado bloqueante na revisão.

---

## 4. Atualização Obrigatória do Grafo de Conhecimento (Graphify)
- Ao final de qualquer etapa que alterou o código-fonte (`feature-implementer`, `bug-fixer`), rode:
  ```bash
  graphify update .
  ```
  Isso garante que o grafo de conhecimento semântico e estrutural (`graphify-out/`, local e não versionado) permaneça sincronizado.

---

## 5. Uso Obrigatório do Pipeline de Agentes Especializados (`.agents/agents/`)
- Cada fase do ciclo de desenvolvimento usa a persona correspondente de `.agents/agents/`:
  - **`feature-implementer`**: Desenvolvimento guiado por TDD com cobertura $\ge 80\%$ e Clean Code.
  - **`bug-fixer`**: Resolução de defeitos com reprodução obrigatória via teste falho (Red) antes da correção (Green).
  - **`code-reviewer`**: Auditoria mecânica independente (comandos do bloco `### <subprojeto>/` do `AGENTS.md` §2: formatação, lint + tipos, testes com cobertura $\ge 80\%$, build) e parecer formal em `docs/reviews/`.
  - **`qa-validator`**: Validação operacional em runtime, segurança (segredos, PII, entradas adversárias) e observabilidade.
- Fluxo, roteamento, invocação em cada ambiente e formatos de relatório: [`.agents/rules/agent-pipeline.md`](agent-pipeline.md).

---

## 6. Comentários
- O código se explica por nomes, tipos e estrutura; não escreva comentário que só narra o que a linha já diz.
- Nos arquivos que você altera, remova comentários narrativos e blocos de código comentado. Fora do diff, registre como nota em vez de editar ("Escopo é o diff" em `agent-pipeline.md`).
- Comentário fica para o *porquê*: decisão arquitetural não óbvia ou advertência de segurança.

---

## 7. Uso Obrigatório e Evidenciação da Skill `pre-pr` ao Final de Toda Implementação
- Ao concluir implementação, refatoração ou correção de bug, rode os gates da skill `pre-pr`.
- O agente deve salvar uma cópia em `docs/pre-pr/<YYYY-MM-DD_HH-mm>_<task>-pre-pr.md` e exibir no fechamento da resposta final o **Relatório Pre-PR Estruturado** com evidências frescas de execução dos comandos.

---

## 8. Execução Obrigatória do Projeto e Verificação em Teste Real ao Final de Cada Execução
- Ao concluir mudança de código em subprojeto executável, suba o projeto e verifique o funcionamento em teste real, conforme [`.agents/rules/real-runtime-verification.md`](real-runtime-verification.md) (mudança sem código executável é isenta, §2.1).
- O agente deve iniciar o serviço, disparar requisições reais contra `/health` e rotas alteradas, validar resposta HTTP 200 e encerrar o processo de forma limpa. No Windows, use `curl.exe` (em Windows PowerShell 5.1 `curl` é alias de `Invoke-WebRequest`); no Linux/macOS, `curl`.

---

## 9. Protocolo de Melhoria Contínua ("Knowledge Suggestion")
- **Gatilho**: falha ou retrabalho cuja causa foi uma regra ou skill de `.agents/` omissa, contraditória ou desatualizada (erro comum de código não conta).
- **Resolução Prévia**: O agente resolve o código e garante testes passando (Green).
- **Proposta Estruturada**: inclua no fechamento um bloco com o diff proposto, para aprovação humana:
  ```markdown
  > [!TIP]
  > ### Proposta de Atualização de Governança
  > - **Problema Identificado**: <descrição concisa do erro ou gargalo>
  > - **Causa Raiz**: <por que a IA ou o código falhou>
  > - **Arquivo a Alterar**: `.agents/skills/<nome>/SKILL.md` ou `.agents/rules/<nome>.md`
  > - **Modificação Proposta**: <diff>
  > - **Impacto Esperado**: Previne que agentes futuros cometam o mesmo erro.
  ```
- **Garantia de Segurança**: mudança em `.agents/rules/` ou `.agents/skills/` só é aplicada depois da aprovação.

---

## 10. Encoding de Arquivos em Scripts `.ps1` e Compatibilidade com Windows PowerShell 5.1
O runtime oficial dos scripts `.ps1` deste projeto é o PowerShell 7 (`pwsh`), nos três sistemas. No Windows, os mesmos scripts continuam compatíveis com o Windows PowerShell 5.1 (pré-instalado no sistema operacional), para quem os invocar manualmente por hábito antigo: sem ternário, sem `??`, e checando `$IsWindows`/`$IsLinux`/`$IsMacOS` só com fallback (essas variáveis automáticas não existem no 5.1; leia-as com `Get-Variable -Name IsWindows -ErrorAction SilentlyContinue`, com fallback para `[Environment]::OSVersion.Platform` ou `[Runtime.InteropServices.RuntimeInformation]::IsOSPlatform(...)`).
- **Scripts `.ps1`**: escreva só em ASCII ou em UTF-8 **com BOM**. O PowerShell 5.1 lê `.ps1` sem BOM na codepage ANSI do sistema, e acentos ou travessões (`—`) viram caracteres corrompidos ou quebram o parser. `pwsh` (7) não tem essa limitação, mas a regra vale para os três sistemas, para manter um único arquivo compatível com ambos os runtimes no Windows.
- **Ler arquivos UTF-8**: use sempre `Get-Content <arquivo> -Encoding UTF8` (ou `-Raw -Encoding UTF8`). Sem o parâmetro, o 5.1 decodifica na codepage ANSI.
- **Gravar arquivos lidos por outras ferramentas**: passe `-Encoding utf8` explicitamente em `Set-Content`, `Add-Content` e `Out-File`; `Set-Content` sem o parâmetro grava em ANSI no 5.1.
- **JSON e Markdown do repositório** continuam UTF-8 (sem BOM); a regra de BOM vale só para `.ps1` que contenha caracteres não ASCII.
