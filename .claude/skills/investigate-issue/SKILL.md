---
name: investigate-issue
description: Investiga um erro, lentidão ou comportamento inesperado da API reproduzindo localmente e correlacionando logs, traces e métricas no Datadog (Logs, APM) com os runbooks do vault, até chegar a uma causa provável com evidência. Use quando o usuário relatar erro 500, falha intermitente, lentidão, teste de integração instável ou um comportamento que não sabe explicar.
argument-hint: <sintoma, endpoint ou mensagem de erro>
---

# investigate-issue

Objetivo: **causa provável com evidência**, não um palpite. Não corrija nada antes de confirmar a causa; a correção começa por um teste vermelho (`.claude/rules/testing.md`).

1. **Sintoma preciso**: endpoint, payload (sem dados pessoais reais), resposta (`ProblemDetails`: `type`, `title`, `status`), quando começou e se é intermitente. Há runbook? `grep -ril "<sintoma>" docs/06-Runbooks`. Se houver, siga-o.
2. **Reproduza localmente**:
   - Rode a API (`dotnet run --project app/src/Api`) e dispare a requisição, ou rode o teste que falha (`dotnet test app/tests/IntegrationTests --filter <Nome>`). Localmente, a evidência é a saída do console do Serilog.
3. **Evidências no Datadog** (ambiente onde o erro ocorreu; filtre por `service` e `env`):
   - **Logs**: janela do erro, `status:error` ou `status:warn`. Pegue o `dd.trace_id`.
   - **APM → Traces**: o trace desse id — qual span falhou ou demorou (`aspnet_core.request`, `http.request` ao downstream).
   - **Métricas**: taxa de erro/latência do endpoint (`trace.aspnet_core.request.errors`, `trace.aspnet_core.request.duration`), se for desempenho.
   - Log ausente no Datadog: confira o CloudWatch Logs do serviço (papel do CloudWatch ainda não definido — `.claude/rules/observability.md`).
4. **Downstream** (se a suspeita for a API externa): no span `http.request`, veja rota, status e duração; reproduza a resposta problemática com um stub WireMock.Net num teste de integração.
5. **Hipóteses** ordenadas por evidência; descarte explicitamente as refutadas e diga como as refutou.
6. **Registre** em `docs/00-Inbox/AAAA-MM-DD-investigacao-<slug>.md`: sintoma, passos de reprodução, evidências (consultas usadas), causa provável e próximos passos. Causa de design ⇒ sugerir spec ou ADR; procedimento recorrente ⇒ sugerir runbook (`docs/99-Templates/TPL-Runbook.md`).
7. Proponha a correção (teste vermelho → fix) e aguarde o usuário decidir se segue.
