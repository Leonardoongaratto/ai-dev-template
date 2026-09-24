---
description: Normaliza o pedido, aprova o plano e dispara feature-implementer → code-reviewer → qa-validator
argument-hint: <pedido ou caminho em docs/prompts/>
---

Siga `.agents/rules/agent-pipeline.md` para o pedido abaixo.

1. Se o pedido não estiver no template, normalize-o em `.agents/rules/prompt-template.md`, quebre por dificuldade (`.agents/rules/prompt-audit-breakdown.md`) e salve em `docs/prompts/`. Apresente o plano e espere aprovação quando algum campo inferido mudar o resultado.
2. Lance o subagente `feature-implementer` com o caminho do arquivo em `docs/prompts/`.
3. Com os gates verdes, lance o `code-reviewer` e, se aprovado, o `qa-validator`, sem esperar novo pedido.
4. Achado bloqueante (Alta ou Média) → `bug-fixer` → volte ao `code-reviewer`. Achados Baixos: o `bug-fixer` corrige na mesma passada, se for barato, sem nova revisão (ver "Proporcionalidade" em `agent-pipeline.md`).
5. Pare antes de commit/push/PR e apresente os vereditos com os caminhos dos relatórios.

Pedido: $ARGUMENTS
