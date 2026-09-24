---
trigger: model_decision
description: Aplicar ao terminar implementação, refatoração ou correção de bug, e antes de um parecer de revisão — define quando e como rodar os gates da skill pre-pr; só quem alterou o código persiste o relatório em docs/pre-pr/.
---

# Regra Obrigatória: Execução e Evidenciação da Skill Pre-PR

Este documento estabelece a diretriz normativa mandatória para a validação de gates pré-PR e comprovação de qualidade via skill **`pre-pr`** ao término de qualquer trabalho de código.

---

## 1. Princípio Fundamental
Nenhuma implementação, refatoração ou correção de bug é considerada concluída com base em afirmações genéricas. O agente deve fornecer **evidência mecânica fresca** executada na sessão atual, garantindo que os comandos do bloco `### <subprojeto>/` do `AGENTS.md` §2 passam (formatação, lint + tipos, testes com cobertura $\ge 80\%$, build) e que o projeto foi testado em runtime real, quando o teste real é exigido.

---

## 2. Momento de Execução Obrigatório (Trigger)
A skill **`pre-pr`** DEVE ser obrigatoriamente executada:
1. **Ao término de qualquer feature ou refatoração** (`feature-implementer`).
2. **Ao término de qualquer correção de bug** (`bug-fixer`).
3. **Antes da emissão de qualquer parecer de revisão** (`code-reviewer`) — **somente as fases 0, 1, 1.1 e 2, sem gravar arquivos** (fora os artefatos que os próprios comandos de build e teste geram). O resultado vai para a seção de gates do relatório em `docs/reviews/`, e as Fases 3, 4 e 5 ficam com quem alterou o código: cada violação vira achado, e a correção fica com o `bug-fixer` ou o implementador.
4. **Sempre que solicitado pelo desenvolvedor** para atestar a prontidão de uma branch.

---

## 3. Diretriz de Execução (Delegação para a Skill)
O agente deve ativar e executar as fases descritas em `.agents/skills/pre-pr/SKILL.md`:
- **Fase 0**: Delimitação do escopo modificado (`git status`, `git diff`).
- **Fase 1**: comandos do bloco `### <subprojeto>/` do `AGENTS.md` §2, dentro do subprojeto afetado (formatação, lint + tipos, testes com cobertura $\ge 80\%$, build).
- **Fase 1.1**: Teste Real em Runtime (`real-runtime-verification.md`).
- **Fase 2**: Auditoria de segurança (zero segredos hardcoded, sem PII em logs, sem supressões).
- **Fase 3**: Sincronização do Grafo de Conhecimento (`graphify update .`), só `feature-implementer` e `bug-fixer`.
- **Fase 4**: Correção mecânica imediata de eventuais violações, só `feature-implementer` e `bug-fixer`.
- **Fase 5**: Emissão e persistência compulsória do Relatório Pre-PR em `docs/pre-pr/<YYYY-MM-DD_HH-mm>_<task>-pre-pr.md`, só `feature-implementer` e `bug-fixer`.

---

## 4. Critérios de Rejeição Compulsória (Blockers)
A entrega de quem alterou o código (`feature-implementer`, `bug-fixer`) será **BLOQUEADA / REJEITADA** se:
1. Não houver comprovação por comandos executados na sessão;
2. A cobertura de testes for inferior a **80%** no componente alterado;
3. O build do subprojeto falhar;
4. O serviço falhar na inicialização em tempo de execução ou não responder HTTP 200 no teste real (quando o teste real é exigido — ver a isenção em `real-runtime-verification.md` §2.1);
5. Existirem supressões de linter (`# noqa`, `# type: ignore`, `//nolint`) ou testes ignorados (`.skip`);
6. O relatório não for exibido no chat e não for persistido em `docs/pre-pr/`;
7. O comando `graphify update .` não tiver sido executado.
