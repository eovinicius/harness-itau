# Query Slice Templates

Files go in `app/src/Application/{Feature}/{UseCase}/`. Queries are reads: no state change, no repository write. Live models: `Todos/GetById/` (single item) and `Todos/Get/` (paged list — but its `UserId` parameter is template legacy, see below).

> `Todos/Get` and `Users/GetById` take `UserId` from the request and answer 403 `UserErrors.Unauthorized()`. That is template legacy (`.claude/rules/security.md`) — new queries take the identity from `IUserContext` and never have a `UserId` parameter.

## Query

Single item:

```csharp
using Application.Abstractions.Messaging;

namespace Application.Todos.GetById;

public sealed record GetTodoByIdQuery(Guid TodoItemId) : IQuery<TodoResponse>;
```

List — always paged (`PagedList<T>`), never `List<T>`:

```csharp
using Application.Abstractions.Messaging;
using Application.Abstractions.Pagination;

namespace Application.Todos.GetOverdue;

public sealed record GetOverdueTodosQuery(int Page, int PageSize) : IQuery<PagedList<TodoResponse>>;
```

## Validator

A query with input has a validator too — `ValidationDecorator` wraps queries as well as commands. Paging is always bounded (model: `Todos/Get/GetTodosQueryValidator.cs`):

```csharp
using FluentValidation;

namespace Application.Todos.GetOverdue;

internal sealed class GetOverdueTodosQueryValidator : AbstractValidator<GetOverdueTodosQuery>
{
    private const int MaxPageSize = 100;

    public GetOverdueTodosQueryValidator()
    {
        RuleFor(q => q.Page).GreaterThanOrEqualTo(1);

        RuleFor(q => q.PageSize).InclusiveBetween(1, MaxPageSize);
    }
}
```

A query whose only input is a route id (e.g. `GetTodoByIdQuery`) needs no validator: the `:guid` route constraint already rejects malformed ids.

## Response DTO

Lives next to the query. Flat, serialization-friendly, never a domain entity.

```csharp
namespace Application.Todos.GetOverdue;

public sealed class TodoResponse
{
    public Guid Id { get; set; }
    public string Description { get; set; }
    public DateTime? DueDate { get; set; }
    public bool IsCompleted { get; set; }
    public DateTime CreatedAt { get; set; }
}
```

Each use-case folder owns its own `TodoResponse` — do not share DTOs across slices even if they look identical today. Return only the fields the use case needs (`.claude/rules/security.md`, LGPD).

## Handler

Scope to the current user, filter, order and page **in the repository** (it forwards them to the downstream and returns `PagedList<{Entity}>`), then map each entity to the slice's DTO:

```csharp
using Application.Abstractions.Authentication;
using Application.Abstractions.Messaging;
using Application.Abstractions.Pagination;
using Application.Abstractions.Repositories;
using Domain.Todos;
using SharedKernel;

namespace Application.Todos.GetOverdue;

internal sealed class GetOverdueTodosQueryHandler(
    ITodoItemRepository todoItemRepository,
    IUserContext userContext,
    IDateTimeProvider dateTimeProvider)
    : IQueryHandler<GetOverdueTodosQuery, PagedList<TodoResponse>>
{
    public async Task<Result<PagedList<TodoResponse>>> Handle(
        GetOverdueTodosQuery query,
        CancellationToken cancellationToken)
    {
        Result<PagedList<TodoItem>> todosResult = await todoItemRepository.GetOverdueAsync(
            userContext.UserId,
            dateTimeProvider.UtcNow,
            query.Page,
            query.PageSize,
            cancellationToken);

        if (todosResult.IsFailure)
        {
            return todosResult.Error;
        }

        PagedList<TodoItem> todos = todosResult.Value;

        return new PagedList<TodoResponse>(
            [.. todos.Items.Select(ToResponse)],
            todos.Page,
            todos.PageSize,
            todos.TotalCount);
    }

    private static TodoResponse ToResponse(TodoItem todoItem) => new()
    {
        Id = todoItem.Id,
        Description = todoItem.Description,
        DueDate = todoItem.DueDate,
        IsCompleted = todoItem.IsCompleted,
        CreatedAt = todoItem.CreatedAt
    };
}
```

- Single-item queries call `GetByIdAsync(id, userContext.UserId, ...)` and propagate the failure with `return result.Error;` — the repository already returns `TodoItemErrors.NotFound(id)` for a missing item **and** for another user's item (404).
- The deterministic order (e.g. by `DueDate`) is part of the repository contract — the downstream must page over a stable order.
- Free-text search is forwarded to the downstream as a query-string parameter, URL-encoded by the repository — never concatenated raw into the URL.
- A new filter or sort ⇒ add it to the `I{Entity}Repository` method and its implementation (`.claude/rules/persistence.md`).
