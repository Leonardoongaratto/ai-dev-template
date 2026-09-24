---
description: Corrige um bug com reprodução Red → Green e reenvia para review
argument-hint: <descrição do bug ou caminho do bugs.md>
---

Lance o subagente `bug-fixer` para: $ARGUMENTS

Ao terminar, lance o `code-reviewer` sobre a correção, conforme `.agents/rules/agent-pipeline.md`.
