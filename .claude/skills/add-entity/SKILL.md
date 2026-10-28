---
name: add-entity
description: Add a new domain entity to the Clean Architecture template — entity class, error catalog, repository interface, and its downstream HTTP implementation. Use when the user asks to add an entity, aggregate, or domain model.
argument-hint: <entity description, e.g. "Project with a name, owner, and list of todos">
---

# Add a Domain Entity

Create a new entity and wire it through every layer, following the `TodoItem` pattern. There is no database: the data belongs to a downstream API reached through a repository (`.claude/rules/persistence.md`).

## Files to create/modify

1. **Entity** — `app/src/Domain/{Feature}/{Entity}.cs`

```csharp
namespace Domain.Projects;

public sealed class Project
{
    private Project()
    {
    }

    public Guid Id { get; private set; }
    public Guid OwnerId { get; private set; }
    public string Name { get; private set; }
    public DateTime CreatedAt { get; private set; }

    public static Project Create(Guid ownerId, string name, DateTime createdAt) =>
        new()
        {
            Id = Guid.NewGuid(),
            OwnerId = ownerId,
            Name = name,
            CreatedAt = createdAt
        };

    public static Project Restore(Guid id, Guid ownerId, string name, DateTime createdAt) =>
        new()
        {
            Id = id,
            OwnerId = ownerId,
            Name = name,
            CreatedAt = createdAt
        };

    public void Rename(string name)
    {
        Name = name;
    }
}
```

**Rich model, never anemic** (`.claude/rules/architecture.md`, Domain): `sealed class`; every property `{ get; private set; }` and a private parameterless constructor; a static `Create(...)` factory that generates the `Id` and copies incoming collections (`[.. labels]`); a static `Restore(...)` factory that rebuilds the full state from the downstream without validating rules (Infrastructure only); one behavior method per state change, returning `Result` with an `{Entity}Errors` error when the rule can fail (`void` when it can't). Non-deterministic values (`DateTime createdAt`) come in as parameters. Collections initialized with `= [];`. No domain events. Live model: `app/src/Domain/Todos/TodoItem.cs`.

2. **Error catalog** — `app/src/Domain/{Feature}/{Entity}Errors.cs`

```csharp
using SharedKernel;

namespace Domain.Projects;

public static class ProjectErrors
{
    public static Error NotFound(Guid projectId) => Error.NotFound(
        "Projects.NotFound",
        $"The project with the Id = '{projectId}' was not found");

    public static readonly Error Unavailable = Error.Failure(
        "Projects.Unavailable",
        "The projects service is unavailable");
}
```

Codes are `"{EntityPlural}.{Reason}"` — the plural of the entity, not of the feature folder (`TodoItem` in `Todos/` → `"TodoItems.NotFound"`). Pick the factory by semantics: `Error.NotFound` (404), `Error.Conflict` (409), `Error.Problem` (400), `Error.Unauthorized` (401), `Error.Forbidden` (403), `Error.Failure` (500). The `Unavailable` error is what the repository returns when the downstream fails or times out.

3. **Repository interface** — `app/src/Application/Abstractions/Repositories/I{Entity}Repository.cs`

```csharp
using Domain.Projects;
using SharedKernel;

namespace Application.Abstractions.Repositories;

public interface IProjectRepository
{
    Task<Result<Project>> GetByIdAsync(Guid projectId, Guid ownerId, CancellationToken cancellationToken);

    Task<Result> AddAsync(Project project, CancellationToken cancellationToken);

    Task<Result> UpdateAsync(Project project, CancellationToken cancellationToken);
}

public sealed record ProjectDto(Guid Id, Guid OwnerId, string Name, DateTime CreatedAt);
```

The transport DTO lives in the Application next to the interface (or in the feature folder); the Infrastructure reuses it to serialize and deserialize — never a duplicate model. Every method returns `Result`/`Result<T>`. Lookups take the owner id (from `IUserContext` in the handler) and return `NotFound` for another user's resource. Lists take filter, sort and `page`/`pageSize` and return `Result<PagedList<{Entity}>>`. Add only the methods the use cases need.

4. **Repository implementation** — `app/src/Infrastructure/{Feature}/{Entity}Repository.cs`, a typed `HttpClient`:

```csharp
using System.Net;
using System.Net.Http.Json;
using Application.Abstractions.Repositories;
using Domain.Projects;
using SharedKernel;

namespace Infrastructure.Projects;

internal sealed class ProjectRepository(HttpClient httpClient) : IProjectRepository
{
    public async Task<Result<Project>> GetByIdAsync(Guid projectId, Guid ownerId, CancellationToken cancellationToken)
    {
        using HttpResponseMessage response = await httpClient.GetAsync($"projects/{projectId}", cancellationToken);

        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            return ProjectErrors.NotFound(projectId);
        }

        if (!response.IsSuccessStatusCode)
        {
            return ProjectErrors.Unavailable;
        }

        ProjectDto? dto = await response.Content.ReadFromJsonAsync<ProjectDto>(cancellationToken);

        if (dto is null || dto.OwnerId != ownerId)
        {
            return ProjectErrors.NotFound(projectId);
        }

        return Project.Restore(dto.Id, dto.OwnerId, dto.Name, dto.CreatedAt);
    }

    // AddAsync / UpdateAsync: same translation — success ⇒ Result.Success(), otherwise the catalog error.
}
```

The downstream route and payload above are illustrative — use the real contract of the downstream API. Never pass the downstream body, raw status, or message on to the caller.

5. **Registration** — in `app/src/Infrastructure/DependencyInjection.cs`:

```csharp
services.AddHttpClient<IProjectRepository, ProjectRepository>(client =>
    client.BaseAddress = new Uri(configuration["Downstream:Projects:BaseUrl"]!));
```

The base address comes from configuration — never hardcoded.

6. **Entity tests** — `app/tests/Application.UnitTests/{Feature}/{Entity}Tests.cs` (model: `Application.UnitTests/Todos/TodoItemTests.cs`): `Create` and every behavior method — success and each failure.

## Rules

- The Domain project references only `SharedKernel` — no infrastructure, no Application types.
- Mapping from the transport DTO to the entity goes only through `Restore(...)` — never open a setter to map (`.claude/rules/persistence.md`).
- Run `dotnet build` and `dotnet test` when done.
- If the user also wants use cases for the entity, continue with the `add-feature` skill.
