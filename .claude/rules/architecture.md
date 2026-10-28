---
paths:
  - "app/src/**"
---
# Arquitetura (Clean Architecture + vertical slices)

## Dependências (apontam para dentro)

```text
Api ──────────────────────► Application ─► Domain ─► SharedKernel
 │                               ▲
 └────► Infrastructure ──────────┘
```

- **SharedKernel**: sem dependências. **Domain**: só SharedKernel — sem dependência de infraestrutura, sem tipos da Application.
- **Application**: Domain + SharedKernel. Dados via interface de repository (`I{Entity}Repository`) ou de service (`I{Servico}Service`); nada de `using Infrastructure.*`.
- **Infrastructure**: implementa abstrações da Application. Clientes downstream com typed `HttpClient` (`IHttpClientFactory`) e resiliência (retry, timeout, circuit breaker). Utiliza os DTOs definidos na Application, sem duplicar modelos de transporte.
- **Api**: depende de Application e Infrastructure. Composição + endpoints finos. Nenhuma regra de negócio.

## Domain (modelo rico)

Modelo: `app/src/Domain/Todos/TodoItem.cs`.

- **Sem entidade anêmica.** Estado só muda por método da entidade: propriedades `{ get; private set; }` (nunca `set`/`init` público).
- Criação por factory estática `{Entity}.Create(...)` (ou verbo de negócio, ex.: `RefreshToken.Issue`): gera o `Id` e copia coleções recebidas (`[.. labels]`).
- Reidratação por factory estática `{Entity}.Restore(...)`: recebe o estado completo vindo do downstream, sem validar regra. Uso exclusivo da Infrastructure; criação nova sempre por `Create`.
- Cada transição é um método com nome de negócio (`Complete`, `Archive`, `UpdateDescription`) que valida a invariante e retorna `Result` quando a regra pode falhar (`void` quando não pode). A falha é o erro do catálogo retornado direto: `return TodoItemErrors.Archived(Id);` (conversão implícita em `SharedKernel/Result.cs`).
- Sem domain events.
- Valores não determinísticos entram por parâmetro (`DateTime utcNow`); a entidade não resolve relógio nem usuário.

## Application (slices)

- Uma pasta por caso de uso: `app/src/Application/{Feature}/{UseCase}/` com `{Verb}{Entity}Command`/`Get{X}Query`, `...Handler`, `...Validator`, `{X}Response`. Modelo: `Todos/Complete/`.
- Handlers `internal sealed`, primary constructor, implementam `ICommandHandler<>`/`IQueryHandler<,>`. Registrados por Scrutor — **sem MediatR, sem registro manual**.
- Validação e logging são transversais (`Abstractions/Behaviors/ValidationDecorator.cs`, `LoggingDecorator.cs`). Não repita isso nos handlers.
- Handler **orquestra**: busca via `I{Entity}Repository` com filtro de propriedade (existência + dono → `{Entity}Errors.NotFound(id)`), chama o método da entidade, propaga a falha (`return result;` se o tipo bate, `return result.Error;` se o handler devolve `Result<T>`), persiste via `I{Entity}Repository`. Falha sempre como `Error` direto — nunca `Result.Failure(...)`/`Result.Failure<T>(...)`. Regra de estado fica na entidade (Domain, acima); o handler não revalida o formato da entrada nem atribui propriedades.
- Chamadas independentes podem ser executadas em paralelo (`Task.WhenAll`) quando seguro e adequado; chamadas dependentes são sequenciais. `CancellationToken` deve ser repassado em todas as chamadas.
- Os DTOs necessários às chamadas downstream ficam na Application, junto à interface do repository/service ou na pasta da feature correspondente. A Infrastructure utiliza esses mesmos tipos para serializar requisições e desserializar respostas, sem criar DTOs duplicados.
- Lógica repetida entre handlers vai para um helper `internal static` da feature (ex.: `Users/RefreshTokenIssuer.cs`), não é copiada.
- Leituras mapeiam a entidade para o DTO do slice, nunca devolvem a entidade; listas retornam `PagedList<T>` paginado pelo repository (busca + ordenação + página repassadas ao downstream).
- Tempo via `IDateTimeProvider`; usuário via `IUserContext`. Propriedade do recurso (padrão e legado do template que não deve ser copiado): `security.md`.
- Validator `internal sealed` para todo command e toda query com entrada além do id da rota — o `ValidationDecorator` envolve os dois. Paginação sempre limitada (modelo: `Todos/Get/GetTodosQueryValidator.cs`). `CreateTodoCommandValidator` e `CopyTodoCommandValidator` (`public class`) são legado.

## Api

- Controller tradicional por feature: `app/src/Api/Controllers/{Feature}Controller.cs`, `public sealed`, herda `ControllerBase`, `[ApiController]`, `[Route("{feature}")]`, `[Tags(Tags.{Feature})]`, `[Authorize]`. Uma action por caso de uso (`Task<IResult>`); a action só monta o command/query, chama o handler injetado com `[FromServices]` e traduz o resultado.
- Tradução de resultado: `result.Match(Results.Ok, CustomResults.Problem)` — nunca monte erro à mão.
- Contrato OpenAPI pelo código: `[EndpointSummary("...")]`, `[ProducesResponseType<T>(StatusCodes.Status200OK)]` e `[ProducesResponseType<ProblemDetails>(status)]` por erro do handler. 401/403, 429 e idempotência são adicionados pelos transformers em `Api/Extensions` (guardados por `IntegrationTests/Api/OpenApiDocumentTests.cs`) — não repita.
- Deduplicação opt-in por filtro de idempotência na action (header `Idempotency-Key`).
- Composição em `Api/Extensions`: uma classe de extensão por preocupação (ex.: `CorsExtensions.cs`, `RateLimitingExtensions.cs`), não um arquivo genérico que acumula registros.
