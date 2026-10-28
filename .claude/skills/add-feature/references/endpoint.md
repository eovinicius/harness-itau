# Controller Templates

One controller per feature in `app/src/Api/Controllers/{Feature}Controller.cs`, one action per use case. Controllers are `public sealed`, inherit `ControllerBase`, carry `[ApiController]`, and are discovered by `AddControllers`/`MapControllers` — no registration needed. Live model: `Controllers/TodosController.cs` (`Archive`, `GetById`).

> The `Create`, `Copy` and `Get` actions of `TodosController` (and `UsersController.GetById`) receive `userId` in the body/query string. That is template legacy — the identity comes from the token, so no request field, route segment or query parameter carries the current user's id.

## Command that creates a resource (POST → 201 + id)

```csharp
using Application.Abstractions.Messaging;
using Application.Projects.Create;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;
using SharedKernel;
using Api.Extensions;
using Api.Infrastructure;

namespace Api.Controllers;

[ApiController]
[Route("projects")]
[Tags(Tags.Projects)]
[Authorize]
public sealed class ProjectsController : ControllerBase
{
    public sealed class CreateRequest
    {
        public string Name { get; set; }
    }

    [HttpPost]
    [EndpointSummary("Create a project")]
    [ProducesResponseType<Guid>(StatusCodes.Status201Created)]
    [ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
    public async Task<IResult> Create(
        [FromBody] CreateRequest request,
        [FromServices] ICommandHandler<CreateProjectCommand, Guid> handler,
        CancellationToken cancellationToken)
    {
        var command = new CreateProjectCommand(request.Name);

        Result<Guid> result = await handler.Handle(command, cancellationToken);

        return result.Match(id => Results.Created($"projects/{id}", id), CustomResults.Problem);
    }
}
```

## Void command from route parameter (PUT/DELETE → 204)

```csharp
[HttpPut("{id:guid}/archive")]
[EndpointSummary("Archive a completed todo")]
[ProducesResponseType(StatusCodes.Status204NoContent)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status404NotFound)]
public async Task<IResult> Archive(
    Guid id,
    [FromServices] ICommandHandler<ArchiveTodoCommand> handler,
    CancellationToken cancellationToken)
{
    var command = new ArchiveTodoCommand(id);

    Result result = await handler.Handle(command, cancellationToken);

    return result.Match(Results.NoContent, CustomResults.Problem);
}
```

## Paged query (GET → 200)

```csharp
[HttpGet("overdue")]
[EndpointSummary("List the current user's overdue todos")]
[ProducesResponseType<PagedList<TodoResponse>>(StatusCodes.Status200OK)]
[ProducesResponseType<ProblemDetails>(StatusCodes.Status400BadRequest)]
public async Task<IResult> GetOverdue(
    [FromQuery] int? page,
    [FromQuery] int? pageSize,
    [FromServices] IQueryHandler<GetOverdueTodosQuery, PagedList<TodoResponse>> handler,
    CancellationToken cancellationToken)
{
    var query = new GetOverdueTodosQuery(page ?? 1, pageSize ?? 10);

    Result<PagedList<TodoResponse>> result = await handler.Handle(query, cancellationToken);

    return result.Match(Results.Ok, CustomResults.Problem);
}
```

The last two are actions of `TodosController` (`[Route("todos")]`, `[Tags(Tags.Todos)]`, `[Authorize]`).

## Rules

- Controller routes are lowercase, plural, no leading slash: `[Route("todos")]`; action templates extend it: `[HttpGet("{id:guid}")]`, `[HttpPut("{id:guid}/archive")]`. Route constraints (`:guid`) on all typed parameters.
- The nested `{UseCase}Request` class exists only when there's a JSON body; it maps 1:1 to the command inside the action. Type enum properties with the domain enum (values still travel as numbers; the OpenAPI schema lists them). Don't put fields in the body that the route already carries — nor the current user's id.
- Success responses: creation → `Results.Created($"{route}/{id}", id)` + `[ProducesResponseType<T>(StatusCodes.Status201Created)]`; void command → `Results.NoContent` + `[ProducesResponseType(StatusCodes.Status204NoContent)]`; read or other returning command → `Results.Ok` + `[ProducesResponseType<T>(StatusCodes.Status200OK)]`.
- Document the contract: `[EndpointSummary(...)]`, the success `[ProducesResponseType...]`, and one `[ProducesResponseType<ProblemDetails>(status)]` per status the handler's errors map to (Validation/Problem → 400, NotFound → 404, Conflict → 409). Use `ProblemDetails`, not `ValidationProblemDetails` — `CustomResults` emits `errors` as a list, not a dictionary. 401/403 for auth, 429 and the idempotency header/409 come from OpenAPI transformers — don't repeat them.
- POST that creates a resource applies the idempotency action filter (opt-in `Idempotency-Key` header).
- Inject the handler interface (`ICommandHandler<...>` / `IQueryHandler<...>`) per action with `[FromServices]` — the decorated instance is injected. No constructor injection of handlers.
- Every controller carries `[Tags(Tags.{Feature})]` and `[Authorize]` (or `[Authorize(Policy = Permissions.X)]` on the action where a permission constant exists). Add the feature constant to `Tags.cs` if new. `[AllowAnonymous]` only if intentional and justified in the PR (like `UsersController.Login`, `Register`, `RefreshToken`).
- Actions return `Task<IResult>`. Failures never get hand-rolled responses — `CustomResults.Problem` translates the `Error` to RFC 7807 ProblemDetails with the right status code.
