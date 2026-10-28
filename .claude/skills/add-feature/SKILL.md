---
name: add-feature
description: Scaffold a complete Clean Architecture feature slice — command or query, custom handler, FluentValidation validator, controller action, and tests (unit, validator, integration). Use when the user asks to add a feature, use case, command, query, or endpoint to this Clean Architecture template.
argument-hint: <feature description, e.g. "archive a todo item" or "get todos due this week">
---

# Add a Feature (Vertical Slice)

Scaffold a full use case following this template's conventions: an Application-layer use case with a custom command/query handler, an Api controller action, and tests. No MediatR — this codebase uses its own `ICommand`/`IQuery` abstractions with Scrutor-registered handlers and decorators.

## Workflow

0. **Spec gate.** If the request cites `SPEC-NNNN` (or a spec in `docs/02-Specs/` covers it), read it first: rules (`RN-n`) drive the handler, acceptance criteria (`AC-n`) drive the tests. Use the domain terms from `docs/01-Product/Glossary.md`. A spec still in `Draft`/`Review` is not ready to implement: say so. **No `Approved` spec** and the request is a new feature, a business-rule change, a new endpoint or an HTTP contract change (`.claude/rules/specs.md`)? Stop and propose the `write-spec` skill instead of scaffolding — a bug fix or internal adjustment goes straight on.
1. **Classify the use case.** A state change is a **command**; a read is a **query**. Derive names from the existing pattern: use case verb + entity, e.g. `ArchiveTodoCommand`, `GetOverdueTodosQuery`.
2. **Check the Domain layer.** If the entity, its `{Entity}Errors` class, or its `I{Entity}Repository` doesn't exist, add it first (see the `add-entity` skill). A command that changes state needs a **behavior method on the entity** (validates the rule, returns `Result`) — add it to the entity with an `{Entity}Tests` test; the handler never assigns properties. Rich domain rules: `.claude/rules/architecture.md` (Domain).
3. **Create the Application slice** in `app/src/Application/{Feature}/{UseCase}/` — command/query, handler, validator (every command, and every query with input beyond a route id), response DTO (queries only). Templates: [references/command-slice.md](references/command-slice.md) and [references/query-slice.md](references/query-slice.md).
4. **Create the action** in `app/src/Api/Controllers/{Feature}Controller.cs` (create the controller if the feature has none). Template: [references/endpoint.md](references/endpoint.md).
5. **Write tests** — handler unit tests, validator tests, and an integration test. Templates: [references/tests.md](references/tests.md).
6. **Verify:** `dotnet build CleanArchitecture.slnx`, then `dotnet test app/tests/Application.UnitTests` — it must pass. Run `dotnet test app/tests/IntegrationTests` too (downstream faked by WireMock.Net, no Docker needed); if they were not run, say so in the report instead of claiming success.

## Non-negotiable conventions

- **Folder = use case.** One folder per use case under `app/src/Application/{Feature}/` (e.g. `Todos/Archive/`), containing all files for that slice.
- **Handlers are `internal sealed`** with primary constructors, implementing `ICommandHandler<TCommand>`, `ICommandHandler<TCommand, TResponse>`, or `IQueryHandler<TQuery, TResponse>`. They orchestrate only: load through the repository (ownership-filtered) → call the entity method → propagate failure → persist through the repository.
- **Every concrete class/record is `sealed`** (commands, DTOs, nested `Request`, tests) — `.claude/rules/csharp.md`.
- **No manual DI registration.** Handlers, validators, and controllers are discovered by assembly scanning (`Scrutor`, `AddValidatorsFromAssembly`, `AddControllers`). Never touch `DependencyInjection.cs` for a new slice.
- **Return `Result` / `Result<T>`, never throw** for expected failures. Errors come from static factory methods on `{Entity}Errors` in the Domain layer, with codes prefixed by the entity plural already used in that catalog (`"TodoItems.NotFound"`, `"Users.NotFound"`).
- **Validation lives in an `internal sealed` `{Command}Validator` / `{Query}Validator`** (FluentValidation), run automatically by `ValidationDecorator` — the handler never validates input shape itself. Which slices need one, paging bounds and the model: `.claude/rules/architecture.md` (Application).
- **Data access via `I{Entity}Repository` or `I{Servico}Service`** (interfaces in the Application, implemented in Infrastructure against the downstream API; `.claude/rules/persistence.md`) — never reference Infrastructure from Application.
- **Ownership** in handlers that act on user-owned data: identity from `IUserContext.UserId` (never a `UserId` in the request), 404 for another user's resource. Model, and the template legacy not to copy: `.claude/rules/security.md`.
- **Queries map to a `{X}Response` DTO** — never return domain entities. Lists return `PagedList<T>`, paged by the repository.
- **Controllers** are `public sealed`, inherit `ControllerBase` with `[ApiController]`, one action per use case. The action injects the handler interface with `[FromServices]` and translates with `result.Match(..., CustomResults.Problem)` — `Results.Created` (POST that creates, plus the idempotency action filter), `Results.NoContent` (void command) or `Results.Ok`. The controller carries `[Tags(Tags.{Feature})]` and `[Authorize]`.

## Naming reference

| Artifact | Pattern | Example |
|---|---|---|
| Command | `{Verb}{Entity}Command` | `ArchiveTodoCommand` |
| Query | `Get{X}Query` | `GetOverdueTodosQuery` |
| Handler | `{Command/Query}Handler` | `ArchiveTodoCommandHandler` |
| Validator | `{Command/Query}Validator` | `ArchiveTodoCommandValidator` |
| Response | `{X}Response` | `TodoResponse` |
| Controller action | `{UseCase}` action in `Controllers/{Feature}Controller.cs` | `TodosController.Archive` |
| Unit test | `{Handler}Tests` | `ArchiveTodoCommandHandlerTests` |
| Test method | `Handle_Should_{Outcome}_When{Condition}` | `Handle_Should_ReturnNotFound_WhenTodoDoesNotExist` |
