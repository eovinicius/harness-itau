---
name: add-tests
description: Backfill missing tests for existing use cases in the Clean Architecture template — handler unit tests, FluentValidation validator tests, and HTTP integration tests. Use when the user asks to add, improve, or backfill test coverage.
argument-hint: <use case or feature to cover, e.g. "CopyTodoCommand" or "the Users feature">
---

# Add Tests for an Existing Use Case

Backfill the three test types this template expects for every slice. Read the target handler/validator/endpoint first, then mirror the structure of the closest existing test class.

## Workflow

1. **Locate the slice.** Find the command/query, handler, validator, and controller action for the target use case. List every distinct outcome: each guard clause (`return {Entity}Errors.X(...)`) and the happy path.
2. **Check what already exists** in `app/tests/Application.UnitTests/{Feature}/` and `app/tests/IntegrationTests/{Feature}/` — extend existing classes, don't duplicate.
3. **Write handler unit tests** — one test per failure path plus one happy path asserting the entity state and the repository write received.
4. **Write validator tests** for every validator the slice has (commands, and queries with input beyond a route id — e.g. `GetTodosQueryValidator`) — one failing test per rule plus one fully-valid command/query.
5. **Write integration tests** — happy path over real HTTP with the downstream faked by WireMock.Net and the expected downstream call asserted; error translation (404/409/400, and downstream failure → 500) where the handler has failure paths; 401 without a token if the route family is new.
6. **Run** `dotnet test app/tests/Application.UnitTests` and `dotnet test app/tests/IntegrationTests`, and fix failures before finishing. If a suite was not run, report its tests as written but not run.

## Conventions

- **Frameworks:** xUnit + Shouldly + NSubstitute; `FluentValidation.TestHelper` for validators. Global usings already cover `Xunit`, `NSubstitute`, `Shouldly`, `SharedKernel`.
- **Unit test doubles:** substitute `I{Entity}Repository`/`I{Servico}Service` and the other interfaces (`IUserContext`, `IDateTimeProvider`, `IPasswordHasher`, `ITokenProvider`) with NSubstitute.
- **Integration test base:** inherit `BaseIntegrationTest(factory)` with the `IntegrationTestWebAppFactory` collection fixture; stub the downstream on `Downstream` (WireMock.Net); use `RegisterAndLoginAsync()` + `Authenticate(token)` for authenticated calls. Define private response DTO records inside the test class (see `TodosTests.TodoDto`).
- **Naming:** classes `{Handler}Tests` / `{Feature}ValidatorsTests` / `{Feature}Tests`; methods `Handle_Should_{Outcome}_When{Condition}` (unit) or `{Action}_Should_{Outcome}[_When{Condition}]` (integration).
- **Structure:** `// Arrange` / `// Act` / `// Assert` comments in every test.
- **Assertions:** compare exact domain errors (`result.Error.ShouldBe(TodoItemErrors.NotFound(id))`); assert the entity state and the write with `Received(1)` on the repository (unit), or the downstream call in `Downstream.LogEntries` (integration).

Full annotated templates: [../add-feature/references/tests.md](../add-feature/references/tests.md) (if the `add-feature` skill is installed) or mirror `CreateTodoCommandHandlerTests`, `TodoValidatorsTests`, and `TodosTests` in this repo.
