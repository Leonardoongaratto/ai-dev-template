---
description: Validação em runtime real contra os critérios de aceite
argument-hint: [slug ou caminho em docs/prompts/]
---

Lance o subagente `qa-validator` para o pedido: $ARGUMENTS

Se houver bugs em `docs/qa/<slug>/bugs.md`, lance o `bug-fixer` e depois volte ao `code-reviewer`, conforme `.agents/rules/agent-pipeline.md`.
