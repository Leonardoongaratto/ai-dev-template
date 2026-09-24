---
description: Revisão independente (opus, sem edição) do diff atual
argument-hint: [slug ou caminho em docs/prompts/]
---

Lance o subagente `code-reviewer` sobre o diff atual do projeto. Contexto do pedido (critérios de aceite): $ARGUMENTS

Se o veredito for REJECTED, lance o `bug-fixer` com os achados e, depois, o `code-reviewer` de novo, conforme `.agents/rules/agent-pipeline.md`.
