---
name: review
description: Revisão independente do diff pelo Claude opus (headless), sem edição de código
---

# Workflow: review

Rode:

```
powershell -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/review-opus.ps1 -Slug <slug> -Context "<caminho em docs/prompts/>"
```

O revisor headless roda somente leitura: ele só imprime o relatório, o script grava essa resposta em `docs/reviews/`, e os achados no `bugs.md` ficam com esta sessão.

- Leia o relatório gerado em `docs/reviews/` e apresente o veredito e todos os achados no diff (só achado bloqueante, Alta ou Média, reprova; Baixos são notas).
- `NOT REVIEWED` (exit 2): informe o usuário. Fallback só se ele aceitar: assuma o papel de `.agents/agents/code-reviewer.md` você mesmo, sem editar código de produção, e registre no relatório "Revisado por: mesmo modelo do implementador".
- REJECTED: registre os achados em `docs/qa/<slug>/bugs.md` (formato de `.agents/rules/agent-pipeline.md`) e siga para `/bugfix`.
