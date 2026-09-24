---
trigger: always_on
description: Consultar o grafo de conhecimento do graphify em graphify-out/ para perguntas de código e arquitetura.
---

## graphify

Este projeto tem um grafo de conhecimento do graphify em graphify-out/, gerado localmente e não versionado (está no `.gitignore`). Num clone novo, ele só existe depois do primeiro `graphify update .`; se `graphify-out/graph.json` não existir, rode esse comando na raiz ou siga sem o grafo.

Regras:
- Para perguntas de código ou arquitetura, quando `graphify-out/graph.json` existir, rode primeiro `graphify query "<pergunta>"` (CLI) ou `query_graph` (MCP). Use `graphify path "<A>" "<B>"` / `shortest_path` para relações e `graphify explain "<conceito>"` / `get_node` para conceitos pontuais. Eles retornam um subgrafo recortado, geralmente bem menor que o `GRAPH_REPORT.md` ou uma busca bruta com grep.
- Se `graphify-out/wiki/index.md` existir, navegue por ele em vez de ler os arquivos brutos.
- Leia `graphify-out/GRAPH_REPORT.md` só para uma revisão ampla de arquitetura ou quando query/path/explain não trouxerem contexto suficiente.
- Depois de modificar arquivos de código nesta sessão, rode `graphify update .` para manter o grafo atualizado (só AST, sem custo de API).
