---
trigger: model_decision
description: Aplicar ao receber pedido de implementação, refatoração ou correção — auditar, quebrar em tarefas por dificuldade e registrar/atualizar o handoff em docs/prompts/. Não se aplica a pergunta, leitura de arquivo ou comando único.
---

# Regra de Auditoria de Prompts, Quebra por Dificuldade e Rastreamento em `docs/prompts/`

Esta regra estabelece o protocolo obrigatório de auditoria, decomposição de tarefas e registro histórico para todo prompt de **implementação ou mudança de comportamento** submetido aos agentes.

---

## 1. Princípio e Propósito

Nenhum prompt de desenvolvimento, refatoração ou correção deve ser executado de forma opaca ou monolítica. Todo prompt deve ser:
1. **Auditado**: Avaliado quanto à viabilidade, impacto arquitetural e aderência aos contratos.
2. **Decomposto por Níveis de Dificuldade**: Fracionado em tarefas atômicas classificadas por complexidade.
3. **Registrado em `docs/prompts/<YYYY-MM-DD_HH-mm>_<slug>.md`**: Documentando formalmente data e hora de criação, o que foi realizado e o backlog remanescente para facilitar o handoff instantâneo para outro agente (`feature-implementer`, `code-reviewer`, `bug-fixer`, `qa-validator`).

**Isenção — pedidos triviais**: pergunta sobre o código, leitura de arquivo ou comando único não passam por auditoria, quebra nem registro em `docs/prompts/`; responda direto. É o mesmo critério de `prompt-template.md` ("Pedido trivial") e da linha "nenhum" do roteamento em `agent-pipeline.md`.

**Isenção — pedidos de dificuldade Baixa**: um pedido cujas tarefas são todas Baixas (tabela abaixo) dispensa o arquivo em `docs/prompts/`; a normalização e o plano ficam na conversa. O registro é obrigatório a partir de Média, ou quando o trabalho vai passar de uma sessão ou de um ambiente para outro (handoff). Ver "Proporcionalidade" em `agent-pipeline.md`.

---

## 2. Níveis de Dificuldade de Tarefas

| Nível | Critérios | Impacto & Risco | Exemplos |
| :--- | :--- | :--- | :--- |
| **Baixa (Low)** | Alterações pontuais, formatação, novos testes unitários diretos, documentação, ajustes de DTOs sem alteração de banco. | Baixo risco de regressão; sem alteração de contratos. | Adicionar validação de campo em schema, novo assert em teste, ajuste de log. |
| **Média (Medium)** | Novos endpoints REST, novos componentes/telas, criação de novo serviço utilitário, refatoração de handlers. | Risco moderado; exige testes unitários e cobertura ≥ 80%. | Nova rota na API, novo componente reutilizável, novo middleware. |
| **Alta (High)** | Alterações em orquestradores de estado, integração com filas/brokers, novo fluxo de autenticação/sessão, migração de módulos legados. | Alto risco de vazamento de estado, timeout ou deadlocks. | Reestruturação de pooling de banco, novo fluxo de autorização multi-tenant. |
| **Crítica (Critical)** | Alterações em contratos de mensageria pública, migrações destrutivas de banco de dados, alterações no proxy de segurança/guardrails, mascaramento de PII. | Risco de quebra de integração em produção, split-brain de banco ou vazamento de dados sensíveis. | Migração estrutural de banco, chaves criptográficas, sanitização de senhas/cartões. |

---

## 3. Template Obrigatório em `docs/prompts/<YYYY-MM-DD_HH-mm>_<slug>.md`

```markdown
# Auditoria de Prompt: <Título da Tarefa>

- **Data e Hora**: YYYY-MM-DD HH:mm
- **Autor do Prompt**: Usuário
- **Agente Responsável**: <Nome do Agente>
- **Status Geral**: EM ANDAMENTO | CONCLUÍDO | BLOQUEADO

---

## 1. Prompt Original e Normalização Canônica
<Incluir o prompt recebido e sua normalização no prompt-template.md>

---

## 2. Quebra de Tarefas e Níveis de Dificuldade

| ID | Tarefa / Subtarefa | Componente / Subprojeto | Dificuldade | Status |
| :--- | :--- | :--- | :--- | :--- |
| T-01 | ... | ... | Baixa / Média / Alta / Crítica | CONCLUÍDO / PENDENTE |
| T-02 | ... | ... | ... | ... |

---

## 3. O Que Foi Feito (Concluído)
- [x] **T-01**: Descrição do que foi implementado.
  - Arquivos modificados: `[caminho/arquivo](../../caminho/arquivo)` (link relativo, nunca `file:///`)
  - Testes executados: `comando de teste` (Resultado: verde, cobertura: XX%)

---

## 4. O Que Falta Ser Aplicado (Pendente / Próximos Passos)
- [ ] **T-02**: Detalhes do que ainda precisa ser codificado ou testado.

---

## 5. Instruções de Handoff para o Próximo Agente
Caso outro agente assuma a execução:
- **Próximo Agente Sugerido**: `feature-implementer` | `code-reviewer` | `bug-fixer` | `qa-validator`
- **Comando de Verificação Atual**: `<comando de testes>`
```
