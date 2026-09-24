---
trigger: model_decision
description: Aplicar ao fechar mudança de código em subprojeto executável (listado ou não em `AGENTS.md` §1) — subir o serviço, testar com requisição real (curl, HTTP 200) e registrar a evidência. Mudanças só de docs, regras ou config de agentes são isentas.
---

# Regra Obrigatória: Execução do Projeto e Teste Real em Runtime

Este documento estabelece a diretriz normativa mandatória para a **execução do projeto e validação de funcionamento em teste real** ao final de qualquer ciclo de desenvolvimento, refatoração ou correção de bugs.

---

## 1. Contexto e Motivação

Testes unitários automatizados com mocks são essenciais para verificar a lógica isolada de componentes, mas **não constituem prova cabal de que a aplicação funciona em runtime**.
Falhas frequentes que passam despercebidas por testes unitários isolados incluem:
- Erros de inicialização do servidor HTTP e vinculação de porta (`bind: address already in use`).
- Variáveis de ambiente ausentes ou mal formatadas carregadas na inicialização (`.env`).
- Panics ou exceções fatais em lifespans, hooks de startup, middlewares globais ou injeção de dependências.
- Configurações incorretas de CORS, roteamento ou serialização JSON em tráfego real.
- Falhas de resolução DNS ou drivers de conexão com bancos de dados, cache ou filas.

Por essa razão, **ao final de cada execução, deve-se obrigatoriamente rodar o projeto e verificar o funcionamento em teste real**.

---

## 2. Princípio Fundamental

> **"Um teste unitário verde não prova um sistema em execução. O projeto deve ser rodado e testado com requisições reais antes de declarar qualquer tarefa concluída."**

Qualquer resposta ou entrega que declare uma tarefa concluída sem evidenciar que o serviço subiu e respondeu a requisições reais em tempo de execução nesta sessão é **sumariamente considerada incompleta e rejeitada**.

### 2.1. Quando o teste real é exigido

- **Exigido**: toda mudança de código (fonte, testes, dependências, configuração de build/servidor) dentro de qualquer **subprojeto executável** (código que sobe como serviço ou app), esteja ou não listado em `AGENTS.md` §1. O §1 é o índice, não a condição: um subprojeto que falte nele é acrescentado na mesma entrega. Ao clonar este template, o §1 não lista nenhum.
- **Isento**: mudança só de documentação, regras (`.agents/rules/`), personas, skills, workflows, comandos, hooks ou configuração de agentes/IDE (`.agents/`, `.claude/`, `.mcp.json`, `AGENTS.md`, `CLAUDE.md`, `GEMINI.md`, `docs/`). Nesses casos, registre no relatório Pre-PR: **"N/A — sem mudança de código executável"**, e rode os scripts alterados com entradas de exemplo quando houver script.
- **Mudança mista**: vale a regra de exigido para o subprojeto afetado.

---

## 3. Protocolo de Execução por Stack

1. **Inicialização em Background**: Iniciar o serviço localmente em segundo plano com o comando de teste real do bloco `### <subprojeto>/` do `AGENTS.md` §2 (ex: `go run main.go`, `uvicorn main:app --port 8000`, `npm run dev`).
2. **Disparo de Requisições Reais**: Efetuar chamadas HTTP reais via `curl.exe` ou cliente HTTP contra o endpoint de saúde `/health` e as rotas afetadas. No PowerShell 5.1, use `curl.exe`: `curl` é alias de `Invoke-WebRequest`, que lê o `-s` como `-SessionVariable` e falha pedindo o parâmetro `Uri`.
3. **Validação de Logs e Status**: Validar resposta com sucesso (ex: `200 OK`), verificar ausência de panics ou exceções fatais nos logs.
4. **Encerramento Limpo (Teardown)**: Finalizar o processo após a coleta de evidências.

---

## 4. Evidência Obrigatória na Resposta e no Relatório Pre-PR

Ao finalizar a execução de uma tarefa, o agente deve incluir explicitamente a evidência do teste real:

```markdown
### Teste Real do Projeto
- **Serviço executado**: `<nome-do-servico>`
- **Comando de subida**: `<comando de subida>`
- **Comando do teste real**: `curl.exe -s http://localhost:<porta>/health`
- **Status HTTP**: `200 OK`
- **Resposta observada**: `{"status": "healthy"}`
- **Logs**: subiu limpo, zero panics, porta vinculada com sucesso.
- **Encerramento**: processo finalizado de forma limpa.
```

---

## 5. Critérios de Rejeição Compulsória

A entrega será **BLOQUEADA / REJEITADA** se:
1. O agente relatar apenas testes unitários e não executar o projeto em runtime, numa mudança em que o teste real é exigido (§2.1).
2. O servidor falhar ao subir devido a portas em conflito, panics ou configurações faltantes.
3. As requisições reais retornarem `500 Internal Server Error`, `Connection Refused` ou `Timeout`.
4. Não houver comprovação visual da resposta da requisição real na mensagem final.
