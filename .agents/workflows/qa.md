---
name: qa
description: Validação em runtime real contra os critérios de aceite, gerando relatório em docs/qa/
---

# Workflow: qa

Assuma o papel definido em `.agents/agents/qa-validator.md`, seguindo `.agents/rules/agent-pipeline.md` e `.agents/rules/real-runtime-verification.md`.

- Não corrija código: grave o relatório em `docs/qa/` e os defeitos em `docs/qa/<slug>/bugs.md`.
- Encerre todo processo que subir.
- Com bugs abertos, siga para `/bugfix`.
