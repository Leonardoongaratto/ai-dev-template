---
name: pre-pr
description: Executa os gates mecânicos do AGENTS.md §2 (formatação, lint + tipos, testes com cobertura >= 80%, build), o teste real em runtime, a auditoria de segurança e emite o Relatório Pre-PR estruturado antes da abertura do PR.
---

# Pre-PR — Gates Automatizados e Revisão

## Regras Invioláveis
1. Verificação do exit code em todo comando.
2. Nunca suprimir (`# noqa`, `//nolint`, `.skip`).
3. Threshold obrigatório de cobertura de testes ≥ 80%.
4. **Teste Real em Runtime Obrigatório**: rodar o projeto e testar com requisições HTTP reais antes de declarar pronto.
5. Salvar cópia do relatório em `docs/pre-pr/<YYYY-MM-DD_HH-mm>_<task>-pre-pr.md`.
6. Exibir o relatório estruturado com evidência fresca diretamente no chat.

## Fases:
- **Fase 0**: Identificar os arquivos modificados (`git status --short`, `git diff --name-only`).
- **Fase 1**: Executar os comandos do bloco `### <subprojeto>/` do `AGENTS.md` §2, dentro do subprojeto afetado (Formatação, Lint + tipos, Testes com cobertura ≥ 80%, Build). Os comandos vivem só lá; esta skill não os repete.
- **Fase 1.1**: Teste Real de Smoke/Integração em Runtime, com o comando de teste real do mesmo bloco do `AGENTS.md` §2 (subir o serviço, `curl.exe` em `/health`, verificar HTTP 200). Exigido só quando há mudança de código em subprojeto executável; mudanças só de docs/regras/config de agentes registram "N/A — sem mudança de código executável" (ver `.agents/rules/real-runtime-verification.md` §2.1).
- **Fase 2**: Auditar segredos, PII, supressões e comentários redundantes.
- **Fase 3**: Atualizar o grafo de conhecimento (`graphify update .`).
- **Fase 4**: Corrigir violações mecânicas diretamente (rerodando as Fases 1 e 1.1).
- **Fase 5**: Emitir e persistir o Relatório Pre-PR.

As Fases 3, 4 e 5 ficam com quem alterou o código (o implementador e o `bug-fixer`). O `code-reviewer` roda só as Fases 0, 1, 1.1 e 2, sem gravar arquivos: não corrige, não atualiza o grafo e não persiste o Relatório Pre-PR. Cada violação vira achado no relatório de review (`.agents/rules/mandatory-pre-pr.md` §2).
