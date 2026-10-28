# Command Slice Templates

Files go in `app/src/Application/{Feature}/{UseCase}/`. Replace `{Feature}` (plural, e.g. `Todos`), `{Entity}` (e.g. `TodoItem`), and use-case names throughout. Live model: `app/src/Application/Todos/Archive/`.

> `Todos/Create` and `Todos/Copy` carry `UserId` in the command and answer 403 `UserErrors.Unauthorized()`. That is template legacy (`.claude/rules/security.md`) — never copy their shape.

## Command

Positional record for few parameters:

```csharp
using Application.Abstractions.Messaging;

namespace Application.Todos.Archive;

public sealed record ArchiveTodoCommand(Guid TodoItemId) : ICommand;
```

Command that creates a resource and returns its id. The owner is **not** a field: the handler takes it from `IUserContext` (example entity from the `add-entity` skill):

```csharp
using Application.Abstractions.Messaging;

namespace Application.Projects.Create;

public sealed record CreateProjectCommand(string Name) : ICommand<Guid>;
```

- `ICommand` → handler returns `Result` (endpoint responds `204 NoContent`).
- `ICommand<TResponse>` → handler returns `Result<TResponse>` (endpoint responds `201 Created` when it creates a resource, `200 Ok` otherwise).

## Validator

`internal sealed`, same folder. Auto-registered (`includeInternalTypes: true`) and executed by `ValidationDecorator` before the handler runs. Every string gets a maximum length. Time-dependent rules inject `IDateTimeProvider` — never `DateTime.Today`/`DateTime.UtcNow`.

```csharp
using FluentValidation;

namespace Application.Projects.Create;

internal sealed class CreateProjectCommandValidator : AbstractValidator<CreateProjectCommand>
{
    public CreateProjectCommandValidator()
    {
        RuleFor(c => c.Name).NotEmpty().MaximumLength(200);
    }
}
```

## Handler

`internal sealed`, primary constructor, `I{Entity}Repository` for data access (`.claude/rules/persistence.md`). The handler **orchestrates**: it loads the entity through the repository filtered by owner (missing or another user's → `NotFound`), calls the entity's behavior method — which enforces the rule and returns `Result` — propagates a failure, persists through the repository, and returns. It never assigns properties (`.claude/rules/architecture.md`, Domain). Model for `ArchiveTodoCommandHandler`; the rule lives in `TodoItem.Archive` (`app/src/Domain/Todos/TodoItem.cs`):

```csharp
using Application.Abstractions.Authentication;
using Application.Abstractions.Messaging;
using Application.Abstractions.Repositories;
using Domain.Todos;
using SharedKernel;

namespace Application.Todos.Archive;

internal sealed class ArchiveTodoCommandHandler(
    ITodoItemRepository todoItemRepository,
    IDateTimeProvider dateTimeProvider,
    IUserContext userContext)
    : ICommandHandler<ArchiveTodoCommand>
{
    public async Task<Result> Handle(ArchiveTodoCommand command, CancellationToken cancellationToken)
    {
        Result<TodoItem> todoItemResult = await todoItemRepository.GetByIdAsync(
            command.TodoItemId,
            userContext.UserId,
            cancellationToken);

        if (todoItemResult.IsFailure)
        {
            return todoItemResult.Error;
        }

        TodoItem todoItem = todoItemResult.Value;

        Result result = todoItem.Archive(dateTimeProvider.UtcNow);

        if (result.IsFailure)
        {
            return result;
        }

        return await todoItemRepository.UpdateAsync(todoItem, cancellationToken);
    }
}
```

Creating handler — the owner comes from the token:

```csharp
internal sealed class CreateProjectCommandHandler(
    IProjectRepository projectRepository,
    IDateTimeProvider dateTimeProvider,
    IUserContext userContext)
    : ICommandHandler<CreateProjectCommand, Guid>
{
    public async Task<Result<Guid>> Handle(CreateProjectCommand command, CancellationToken cancellationToken)
    {
        var project = Project.Create(userContext.UserId, command.Name, dateTimeProvider.UtcNow);

        Result result = await projectRepository.AddAsync(project, cancellationToken);

        if (result.IsFailure)
        {
            return result.Error;
        }

        return project.Id;
    }
}
```

Notes:
- **Ownership (single pattern)**: pass `userContext.UserId` to the repository lookup; it returns `{Entity}Errors.NotFound` (404) when nothing matches — another user's resource is indistinguishable from a missing one. Never compare a request `UserId` and never answer 403 `UserErrors.Unauthorized()` for ownership.
- `IDateTimeProvider` (from `SharedKernel`) for timestamps — never `DateTime.UtcNow` directly.
- For a returning command (`ICommand<Guid>`), return the value directly — `Result<T>` has an implicit conversion: `return project.Id;`.

## Domain additions (if needed)

Behavior method on the entity — the rule and the state change live together. Model for `TodoItem.Archive`:

```csharp
public Result Archive(DateTime archivedAt)
{
    if (IsArchived)
    {
        return Result.Success();
    }

    if (!IsCompleted)
    {
        return TodoItemErrors.NotCompleted(Id);
    }

    IsArchived = true;
    ArchivedAt = archivedAt;

    return Result.Success();
}
```

Return `Result` when the rule can fail, `void` when it can't (`Unarchive`). Cover it in `app/tests/Application.UnitTests/{Feature}/{Entity}Tests.cs` (model: `TodoItemTests.cs`).

Error factory on the existing `{Entity}Errors` class in `app/src/Domain/{Feature}/`. The code prefix is the **plural of the entity** — the one already used by that catalog (`TodoItemErrors` → `"TodoItems.*"`, `UserErrors` → `"Users.*"`), not the feature folder name:

```csharp
public static Error NotCompleted(Guid todoItemId) => Error.Problem(
    "TodoItems.NotCompleted",
    $"The todo item with Id = '{todoItemId}' must be completed before it can be archived.");
```

Error type → HTTP status (via `CustomResults.Problem`): `NotFound` → 404, `Conflict` → 409, `Problem`/`Validation` → 400, `Unauthorized` → 401, `Forbidden` → 403, `Failure` → 500.

A use case that needs a repository method that doesn't exist yet adds it to `I{Entity}Repository` and its Infrastructure implementation (`add-entity` skill, steps 3–4).
