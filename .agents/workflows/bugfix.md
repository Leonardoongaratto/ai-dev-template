---
name: bugfix
description: Corrige um bug com reprodução Red → Green e reenvia para a revisão cruzada
---

# Workflow: bugfix

Assuma o papel definido em `.agents/agents/bug-fixer.md`, seguindo `.agents/rules/agent-pipeline.md`.

1. Reproduza com um teste que falha antes de tocar no código de produção.
2. Corrija a causa raiz e registre Status, Causa raiz, Correção e Testes de regressão na entrada de `docs/qa/<slug>/bugs.md` (se existir).
3. Com os gates verdes, rode `/review` novamente.
