---
paths:
  - "app/src/**"
---
# Arquitetura (BFF: Clean Architecture enxuta + vertical slices)

BFF: não é dono de dados, não tem Domain nem banco próprio. Orquestra APIs downstream, agrega e entrega no formato da tela.

## Dependências (apontam para dentro)

```text
Api ──────────────────► Application ─────► Shared
 │                           ▲
 └────► Infrastructure ──────┘
```

- **Shared**: sem dependências. Só primitivos transversais (`Result`, `Result<T>`, `Error`, `ErrorType`) — nada de regra de negócio.
- **Application**: depende somente de Shared. Downstream só via interfaces de cliente da própria Application (`I{Service}Client`); nada de `using Infrastructure.*` nem `HttpClient` direto.
- **Infrastructure**: depende de Application e implementa suas abstrações. Clientes downstream com typed `HttpClient` (`IHttpClientFactory`), resiliência (retry, timeout, circuit breaker) e propagação do token do usuário. Utiliza os DTOs definidos na Application, sem duplicar modelos de transporte.
- **Api**: depende de Application e Infrastructure. É responsável pela composição das dependências e pelos endpoints finos. Nenhuma regra de negócio.

## Downstream

- Sem entidade, `DbContext` ou migration. Os dados pertencem aos serviços downstream.
- Uma interface por serviço downstream em `Application/Abstractions/` (ou na pasta da feature quando só ela usa), retornando `Result`/`Result<T>`.
- Os DTOs necessários às chamadas downstream ficam na Application, junto à abstração do cliente ou na pasta da feature correspondente. A Infrastructure utiliza esses mesmos tipos para serializar requisições e desserializar respostas, sem criar DTOs duplicados.
- O cliente traduz falhas downstream para `Error` do catálogo `{Feature}Errors`:
  - 404 downstream ⇒ `{Feature}Errors.NotFound(id)`.
  - Indisponibilidade/timeout ⇒ erro de falha do catálogo.
  - Nunca repasse corpo, status bruto ou mensagem do downstream ao consumidor.
- Chamadas independentes podem ser executadas em paralelo (`Task.WhenAll`) quando seguro e adequado; chamadas dependentes são sequenciais. Propagação de `CancellationToken`: `csharp.md`.

## Application (slices)

### Estrutura

- Uma pasta por caso de uso: `app/src/Application/{Feature}/{UseCase}/` com `{Verb}{Feature}Command`/`Get{X}Query`, `...Handler`, `...Validator` e `{X}Response`.
- Handlers `internal sealed`, primary constructor, implementam `ICommandHandler<>`/`IQueryHandler<,>`. Registrados por Scrutor — sem MediatR e sem registro manual por handler.
- Validação e logging são transversais (`Abstractions/Behaviors/ValidationDecorator.cs`, `LoggingDecorator.cs`). Não repita essas responsabilidades nos handlers.
- Validator `internal sealed` para todo command e toda query com entrada além do ID da rota — o `ValidationDecorator` envolve ambos. Paginação sempre limitada.

### Handler

- Handler **orquestra**, nesta ordem:
  1. Chama os clientes downstream.
  2. Propaga a falha: `return result;` se o tipo bate, `return result.Error;` se o handler devolve `Result<T>`.
  3. Agrega e mapeia para o `{X}Response` do slice (formato da tela).
- Falha sempre como `Error` direto — nunca `Result.Failure(...)`/`Result.Failure<T>(...)`.
- A regra de agregação/apresentação fica no handler. O handler não revalida o formato da entrada.
- Lógica repetida entre handlers vai para um helper `internal static` da feature, não é copiada.
- Tempo via `IDateTimeProvider`; usuário via `IUserContext`.
- Identidade sempre obtida do token, repassada ao downstream — nunca do payload. Demais regras de propriedade do recurso: `security.md`.

### Listas

- Paginação repassada ao downstream; o response espelha o envelope paginado (itens, página, total).

## Api

### Controller

- Controller tradicional por feature: `app/src/Api/Controllers/{Feature}Controller.cs`.
  - `public sealed`, herda `ControllerBase`.
  - `[ApiController]`, `[Route("{feature}")]`, `[Tags(Tags.{Feature})]`, `[Authorize]`.
- Uma action por caso de uso (`Task<IResult>`): só monta o command/query, chama o handler injetado com `[FromServices]` e traduz o resultado.
- Tradução de resultado: `result.Match(Results.Ok, CustomResults.Problem)` — nunca monte erros manualmente.
- Deduplicação opt-in por filtro de idempotência na action, usando o header `Idempotency-Key`.

### Contrato OpenAPI

- Declarado pelo código: `[EndpointSummary("...")]`, `[ProducesResponseType<T>(StatusCodes.Status200OK)]` e `[ProducesResponseType<ProblemDetails>(status)]` para cada erro possível do handler.
- 401/403, 429 e idempotência são adicionados pelos transformers em `Api/Extensions` — não repita.

### Composição

- Em `Api/Extensions`: uma classe de extensão por preocupação (ex.: `CorsExtensions.cs`, `RateLimitingExtensions.cs`, `DownstreamClientsExtensions.cs`), não um arquivo genérico que acumula registros.
