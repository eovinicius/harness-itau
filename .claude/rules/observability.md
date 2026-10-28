---
paths:
  - "app/src/**"
  - "docker-compose*.yml"
---

# Observabilidade (Serilog + dd-trace-dotnet → Datadog; AWS CloudWatch)

Traces e métricas de APM: tracer `dd-trace-dotnet` → Datadog Agent. Infra na AWS, provisionada via Terraform (fora deste repositório). Mapa de sinais: `docs/03-Architecture/Observability.md`. Skill: `instrument-observability`.

- **Setup único**: o `dd-trace-dotnet` instrumenta automaticamente ASP.NET Core e HttpClient; logs via Serilog configurado em `appsettings*.json`. Não adicione exporter OpenTelemetry, `TracerProvider` nem sink paralelo — duplica spans e logs.
- **Configuração do tracer por ambiente**: `DD_SERVICE`, `DD_ENV`, `DD_VERSION` (unified service tagging) e `DD_AGENT_HOST`/`DD_TRACE_AGENT_URL` vêm das variáveis de ambiente do deploy, nunca de `appsettings*.json` ou do código. `DD_API_KEY` pertence ao Datadog Agent, nunca à aplicação (`security.md`).
- **Span manual e métrica de negócio**: biblioteca ainda **não definida** (API `Datadog.Trace`, `ActivitySource` com `DD_TRACE_OTEL_ENABLED` ou DogStatsD). Antes de criar, pergunte ou registre em `docs/00-Inbox/`; pacote novo passa por ADR (core #4 e #8). Latência e erro por endpoint já saem do APM (`trace.aspnet_core.request.*`) — não recrie.
- **Nomes**: métrica `app.<contexto>.<medida>`; span manual `<verbo> <objeto>`.
- **Cardinalidade baixa** em tags de métrica: só enums/flags — nunca ids, e-mail, texto livre ou mensagem de erro. No Datadog, cada combinação de tags vira uma custom metric cobrada.
- **Logs**: estruturados; Information para eventos de negócio, Warning para falha esperada, Error para inesperada. O `LoggingDecorator` já registra cada command/query — não duplique.
- **Nunca logar/tagear PII** (conteúdo livre informado pelo usuário, nome, e-mail, telefone), tokens ou connection strings.
- **Correlação** log ↔ trace pelo tracer (`DD_LOGS_INJECTION=true` injeta `dd.trace_id`/`dd.span_id` no Serilog). Não crie IDs de correlação próprios.
- **CloudWatch**: papel ainda **não definido** (destino de logs, métricas de infra ou alarmes). Não adicione sink, SDK ou exporter da AWS para CloudWatch sem decisão registrada.
- **Validação local**: ainda **não definida** — não suba stack de observabilidade no `docker-compose*.yml` sem decisão. Até lá, confira a saída do console do Serilog e, no ambiente de dev, o Datadog (APM → Traces, Logs), filtrando por `service` e `env`.
- Sinal novo ou renomeado ⇒ atualizar `docs/03-Architecture/Observability.md` no mesmo PR.
