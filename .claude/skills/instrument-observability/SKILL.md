---
name: instrument-observability
description: Adiciona métricas de negócio, spans e logs estruturados no padrão Serilog + dd-trace-dotnet do repositório (exportados para o Datadog), com controle de cardinalidade e sem dados pessoais. Use quando uma spec pedir métricas ou SLIs, ao investigar falta de visibilidade, ou ao criar spans e logs para um fluxo novo.
argument-hint: <o que precisa ser observado, ex.: "tarefas concluídas por prioridade">
---

# instrument-observability

Regras: `.claude/rules/observability.md`. Setup existente: `dd-trace-dotnet` (auto-instrumentação de ASP.NET Core e HttpClient, configurado pelas variáveis `DD_*` do ambiente) + Serilog em `appsettings*.json`.

1. **Defina a pergunta** que o sinal responde (ex.: "quantas tarefas são concluídas por prioridade?") e a unidade (`ms`, `s`, `{todo}`).
2. **Já existe?** Latência, taxa de erro e volume por endpoint e por chamada ao downstream já saem do APM (spans `aspnet_core.request` e `http.request`, métricas `trace.aspnet_core.request.*`). Se a pergunta é essa, não crie sinal — aponte a consulta no Datadog.
3. **Métrica ou span manual**: a biblioteca ainda não foi definida (rule). Pare e pergunte ao usuário qual usar; sem resposta, registre a pendência em `docs/00-Inbox/` e, se exigir pacote novo, `create-adr`. Com a decisão tomada:
   - Instrumento nomeado `app.<contexto>.<medida>` (ex.: `app.todos.completed`, com a tag `priority` — enum `Domain/Todos/Priority.cs`).
   - Tags **apenas** de baixa cardinalidade (enums, bool). Nunca ids, e-mail, texto livre ou mensagem de erro.
   - Span só se não houver auto-instrumentação cobrindo o trabalho; nome `verbo objeto`; em falha, marque o span como erro.
4. **Logs**: `ILogger<T>` com template estruturado e o nível certo. O `LoggingDecorator` já registra cada command/query — não duplique. Nada de dados pessoais.
5. **Teste** (métricas críticas): cubra no teste do handler com o recurso de teste da biblioteca escolhida. Se o pacote não existir em `Directory.Packages.props`, peça confirmação antes de adicionar.
6. **Confira**: validação local ainda não definida (rule) — use a saída do console do Serilog. No ambiente de dev, veja no Datadog (APM → Traces, Logs, Metrics → Explorer) filtrando por `service` e `env`.
7. **Docs**: linha nova na tabela "Sinais de negócio" de `docs/03-Architecture/Observability.md`.
