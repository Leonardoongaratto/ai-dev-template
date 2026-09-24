---
trigger: model_decision
description: Aplicar a todo pedido de implementação ou mudança de comportamento — normalizar no template canônico (task, goal, requirements, api_contracts, acceptance_criteria, constraints) antes de tocar em código. Pedidos triviais são isentos.
---

# Template Padrão de Prompt (Obrigatório)

Todo pedido do usuário neste projeto segue o template canônico em `.agents/rules/prompt-template.md`:
`<task>`, `<goal>`, `<requirements>` (Business / Architecture / UI/UX), `<api_contracts>`, `<acceptance_criteria>`, `<constraints>` — nesta ordem, com qualquer bloco vazio marcado `N/A`.

- **Pedido já no template**: execute diretamente. `<acceptance_criteria>` = definição de pronto; `<constraints>` = limite rígido de escopo.
- **Pedido livre** (uma linha, relato de bug, pedido curto): reescreva-o no template **antes de tocar em código**, apresente a versão normalizada marcando todo campo inferido com `?`, e só prossiga sem confirmação quando nenhum campo inferido mudar o resultado do trabalho.
- **Pedido trivial** (pergunta sobre o código, leitura de arquivo, comando único): sem normalização. O template vale para pedidos de implementação ou mudança de comportamento.
- **Auditoria e Quebra por Dificuldade**: Todo prompt auditado deve ser decomposto em tarefas classificadas por complexidade (Baixa, Média, Alta, Crítica) e registrado em `docs/prompts/<YYYY-MM-DD_HH-mm>_<slug>.md`, mantendo o que foi feito e o que falta para o handoff entre agentes. Pedido só com tarefas de dificuldade Baixa dispensa o registro (`prompt-audit-breakdown.md`).
- **Criação/Geração de Prompts (Obrigatório em `docs/prompts/`)**: Toda vez que o usuário pedir para criar, gerar ou estruturar um prompt, formate-o no template canônico e **salve-o obrigatoriamente** como um arquivo Markdown em `docs/prompts/<YYYY-MM-DD_HH-mm>_<slug>.md`.

Cada item de `<acceptance_criteria>` vira um caso de teste, respeitando a regra de cobertura ≥ 80%.

---

## Estrutura

```xml
<task>
Título curto do pedido (uma linha).
</task>

<goal>
Objetivo de negócio em 1–3 frases: o que o usuário final passa a poder fazer, e por quê.
</goal>

<requirements>
Business:
- Regra de negócio observável.

Architecture:
- Onde o código vive (módulo, tela, hook de domínio, slice, repositório) e quem é responsável pelo quê.

UI/UX:
- Comportamento visual, estados (carregando, erro, vazio, sucesso), i18n, responsividade.
</requirements>

<api_contracts>
External APIs:
- Serviço, endpoint, autenticação.

Backend APIs:
- METHOD /rota — propósito.
- Resposta de sucesso: formato esperado.
- Respostas de erro: códigos e significado.
</api_contracts>

<acceptance_criteria>
- Given <contexto>, when <ação>, then <resultado observável>.
</acceptance_criteria>

<constraints>
- DO: obrigação explícita.
- DO NOT: proibição de escopo.
- NEVER: proibição absoluta (segurança, dado sensível, dependência paga).
</constraints>
```
