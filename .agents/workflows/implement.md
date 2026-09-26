---
name: implement
description: Normaliza o pedido e implementa como feature-implementer, entregando para a revisão cruzada em opus
---

# Workflow: implement

Siga `.agents/rules/agent-pipeline.md`.

1. Se o pedido não estiver no template, normalize em `.agents/rules/prompt-template.md`, quebre por dificuldade (`.agents/rules/prompt-audit-breakdown.md`) e salve em `docs/prompts/`. Apresente o plano e espere aprovação quando algum campo inferido mudar o resultado.
2. Assuma o papel definido em `.agents/agents/feature-implementer.md` e implemente.
3. Com todos os gates verdes, faça o handoff automático: rode `pwsh -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/review-opus.ps1 -Slug <slug> -Context "<caminho em docs/prompts/>"`.
4. Se o veredito for REJECTED, registre os achados em `docs/qa/<slug>/bugs.md` e rode `/bugfix` e repita o passo 3. Se for NOT REVIEWED, diga isso ao usuário — nunca trate como aprovação.
5. Com o review aprovado, rode `/qa`.
6. Pare antes de commit/push/PR.
