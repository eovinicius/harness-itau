# Test Templates

Stack: xUnit + Shouldly + NSubstitute (unit), FluentValidation.TestHelper (validators), WebApplicationFactory + WireMock.Net faking the downstream APIs (integration). Every new use case gets all three. Live models: `Application.UnitTests/Todos/ArchiveTodoCommandHandlerTests.cs`, `GetTodosQueryValidatorTests.cs`, `IntegrationTests/Todos/TodoArchivingTests.cs`.

## Handler unit tests

`app/tests/Application.UnitTests/{Feature}/{UseCase}{Command|Query}HandlerTests.cs`. Substitute `I{Entity}Repository`/`I{Servico}Service` and the other interfaces (`IUserContext`, `IDateTimeProvider`) with NSubstitute. Build the handler and the entity through private helpers so each test reads as the behavior it proves.

Cover: each failure path (one test per guard clause, including a repository failure), the happy path (entity state changed + repository write received) and **repository `NotFound` → `NotFound`** (another user's resource).

```csharp
using Application.Abstractions.Authentication;
using Application.Abstractions.Repositories;
using Application.Todos.Archive;
using Domain.Todos;
using SharedKernel;

namespace Application.UnitTests.Todos;

public sealed class ArchiveTodoCommandHandlerTests
{
    private static readonly Guid UserId = Guid.NewGuid();
    private static readonly DateTime Now = new(2026, 10, 18, 12, 0, 0, DateTimeKind.Utc);

    private readonly ITodoItemRepository _todoItemRepository = Substitute.For<ITodoItemRepository>();

    [Fact]
    public async Task Handle_Should_ArchiveAndUpdateTodo_WhenTodoIsCompleted()
    {
        // Arrange
        TodoItem todoItem = CreateTodo(isCompleted: true);
        _todoItemRepository.GetByIdAsync(todoItem.Id, UserId, Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(Result.Success(todoItem)));
        _todoItemRepository.UpdateAsync(todoItem, Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(Result.Success()));
        ArchiveTodoCommandHandler handler = CreateHandler();

        // Act
        Result result = await handler.Handle(new ArchiveTodoCommand(todoItem.Id), CancellationToken.None);

        // Assert
        result.IsSuccess.ShouldBeTrue();
        todoItem.IsArchived.ShouldBeTrue();
        todoItem.ArchivedAt.ShouldBe(Now);
        await _todoItemRepository.Received(1).UpdateAsync(todoItem, Arg.Any<CancellationToken>());
    }

    [Fact]
    public async Task Handle_Should_ReturnNotFound_WhenTodoBelongsToAnotherUser()
    {
        // Arrange
        var todoItemId = Guid.NewGuid();
        _todoItemRepository.GetByIdAsync(todoItemId, UserId, Arg.Any<CancellationToken>())
            .Returns(Task.FromResult(Result.Failure<TodoItem>(TodoItemErrors.NotFound(todoItemId))));
        ArchiveTodoCommandHandler handler = CreateHandler();

        // Act
        Result result = await handler.Handle(new ArchiveTodoCommand(todoItemId), CancellationToken.None);

        // Assert
        result.IsFailure.ShouldBeTrue();
        result.Error.ShouldBe(TodoItemErrors.NotFound(todoItemId));
        await _todoItemRepository.DidNotReceiveWithAnyArgs().UpdateAsync(default!, default);
    }

    private ArchiveTodoCommandHandler CreateHandler()
    {
        IUserContext userContext = Substitute.For<IUserContext>();
        userContext.UserId.Returns(UserId);
        IDateTimeProvider dateTimeProvider = Substitute.For<IDateTimeProvider>();
        dateTimeProvider.UtcNow.Returns(Now);

        return new ArchiveTodoCommandHandler(_todoItemRepository, dateTimeProvider, userContext);
    }

    private static TodoItem CreateTodo(bool isCompleted)
    {
        // State is reached through the entity's own methods.
        var todoItem = TodoItem.Create(UserId, "Existing todo", Priority.Low, null, [], Now);

        if (isCompleted)
        {
            todoItem.Complete(Now);
        }

        return todoItem;
    }
}
```

Conventions:
- Test names: `Handle_Should_{Outcome}_When{Condition}`.
- `// Arrange` / `// Act` / `// Assert` comments in every test.
- Assert failures by comparing the exact error (`result.Error.ShouldBe(TodoItemErrors.NotFound(id))`) or its code (`result.Error.Code.ShouldBe("TodoItems.NotCompleted")`) — follow the neighboring test.
- Assert writes with `Received(1)` on the repository method; a failure path asserts `DidNotReceiveWithAnyArgs()` on the write.
- Fixed instants (`Now`) instead of `DateTime.UtcNow` when the test asserts time.
- `GlobalUsings.cs` already imports `Xunit`, `NSubstitute` and `Shouldly` — don't re-add those usings. `SharedKernel` is **not** global: add `using SharedKernel;` when the test uses `Result`/`Error`.
- Build the entity through `Create` and behavior methods (or `Restore` when the test needs a downstream state the methods can't reach) — never object initializers, opened setters or reflection (`.claude/rules/testing.md`). A new behavior method also gets an `{Entity}Tests` test.
- Test classes and nested helper types are `sealed`.

## Validator tests

`app/tests/Application.UnitTests/{Feature}/{Validator}Tests.cs` for a single validator (e.g. `GetTodosQueryValidatorTests`), or extend the feature's shared file if one exists (`TodoValidatorsTests`).

```csharp
using Application.Todos.Get;
using FluentValidation.TestHelper;

namespace Application.UnitTests.Todos;

public sealed class GetTodosQueryValidatorTests
{
    private readonly GetTodosQueryValidator _validator = new();

    [Theory]
    [InlineData(0)]
    [InlineData(101)]
    public void Validator_Should_HaveError_WhenPageSizeIsOutOfRange(int pageSize)
    {
        // Arrange
        GetTodosQuery query = CreateQuery(page: 1, pageSize: pageSize);

        // Act
        TestValidationResult<GetTodosQuery> result = _validator.TestValidate(query);

        // Assert
        result.ShouldHaveValidationErrorFor(q => q.PageSize);
    }
}
```

Cover each rule's failure plus one fully-valid input (`ShouldNotHaveAnyValidationErrors`), including the limits (max length, max page size). Validators are `internal`: the test project already sees them via `InternalsVisibleTo`.

## Integration tests

`app/tests/IntegrationTests/{Feature}/{Feature}Tests.cs` or a file per capability (`TodoArchivingTests.cs`). Inherit `BaseIntegrationTest(factory)` — it runs the real API with the downstream base addresses pointed at a WireMock.Net server, and provides `HttpClient`, `Downstream` (the `WireMockServer`), `RegisterAndLoginAsync()`, and `Authenticate(token)`. Tests go through real HTTP, never call handlers directly. Stub the downstream per test; declare private response records in the class (`ProblemDto`).

```csharp
public sealed class TodoArchivingTests(IntegrationTestWebAppFactory factory) : BaseIntegrationTest(factory)
{
    private sealed record ProblemDto(string Title, int Status);

    [Fact]
    public async Task ArchiveTodo_Should_UpdateCompletedTodoDownstream()
    {
        // Arrange
        (Guid userId, AccessTokens tokens) = await RegisterAndLoginAsync();
        Authenticate(tokens.AccessToken);
        var todoId = Guid.NewGuid();
        StubCompletedTodo(todoId, userId);

        // Act
        HttpResponseMessage response = await HttpClient.PutAsync($"todos/{todoId}/archive", null);

        // Assert
        response.StatusCode.ShouldBe(HttpStatusCode.NoContent);
        Downstream.LogEntries.ShouldContain(entry =>
            entry.RequestMessage.Method == "PUT" && entry.RequestMessage.Path == $"/todos/{todoId}");
    }

    [Fact]
    public async Task ArchiveTodo_Should_ReturnNotFound_WhenTodoBelongsToAnotherUser()
    {
        // Arrange
        (_, AccessTokens tokens) = await RegisterAndLoginAsync();
        Authenticate(tokens.AccessToken);
        var todoId = Guid.NewGuid();
        StubCompletedTodo(todoId, ownerId: Guid.NewGuid());

        // Act
        HttpResponseMessage response = await HttpClient.PutAsync($"todos/{todoId}/archive", null);

        // Assert
        response.StatusCode.ShouldBe(HttpStatusCode.NotFound);
        ProblemDto? problem = await response.Content.ReadFromJsonAsync<ProblemDto>();
        problem!.Title.ShouldBe("TodoItems.NotFound");
    }

    private void StubCompletedTodo(Guid todoId, Guid ownerId)
    {
        Downstream
            .Given(Request.Create().WithPath($"/todos/{todoId}").UsingGet())
            .RespondWith(Response.Create()
                .WithStatusCode(200)
                .WithBodyAsJson(new { id = todoId, userId = ownerId, isCompleted = true }));

        Downstream
            .Given(Request.Create().WithPath($"/todos/{todoId}").UsingPut())
            .RespondWith(Response.Create().WithStatusCode(204));
    }
}
```

Stub helpers (`StubCompletedTodo`) live in the test class and mirror the real downstream contract. Also stub a downstream failure (500/timeout) once per repository method to prove it becomes the catalog's `Failure` error — never the downstream body or status.

Minimum coverage per endpoint: one unauthorized test (no token → 401) if it's a new route family, one happy-path test asserting the downstream call was received, one failure translation test per handler failure (status + `Title` = error code), and one test that another user's resource answers 404.

## Run

```
dotnet test app/tests/Application.UnitTests
dotnet test app/tests/IntegrationTests
```

Integration tests need no Docker: WireMock.Net fakes the downstream in-process.
