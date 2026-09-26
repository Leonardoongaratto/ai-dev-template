---
name: graphify
description: Transforma qualquer pasta de arquivos em um grafo de conhecimento navegável
---

# Workflow: graphify

Siga a skill do graphify instalada globalmente pelo setup (`.agents/scripts/setup-agents.ps1`, via `graphify install --platform claude` / `--platform antigravity`, quando `graphify` está no PATH). Ela não é distribuída neste template — é de terceiros (Graphify-Labs, licença Apache-2.0) e fica em `~/.claude/skills/graphify/SKILL.md` (Claude Code) ou `~/.gemini/config/skills/graphify/SKILL.md` (Antigravity/Gemini). A instalação para o Claude Code também registra a skill em `~/.claude/CLAUDE.md`, que vale para todos os projetos do usuário. Para não gravar nada fora do repositório, rode o setup com `-SkipGraphifyInstall`.

Se a skill não aparecer disponível, rode o setup primeiro:

```
pwsh -NoProfile -ExecutionPolicy Bypass -File .agents/scripts/setup-agents.ps1
```

Se nenhum caminho for informado, use `.` (diretório atual).
