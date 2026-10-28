---
name: ca-review
description: Quick inline review of work in progress against this repository's Clean Architecture conventions — layer boundaries, rich domain model, slice structure, Result-based errors, validation, resource ownership, endpoint contract, logging of personal data, downstream repositories, and test coverage. Use whenever the user asks to check, review, or sanity-check a file, slice, handler, endpoint, or their pending changes against the project's patterns ("does this follow the conventions?", "check my slice", "is this handler right?"), even if they never say "conventions". For hunting logic bugs use the code-reviewer subagent; for the full pre-PR review with security, use the /review command.
argument-hint: '[optional: files, folder, or feature to review; defaults to everything the branch changed]'
---

# Clean Architecture Convention Review

Report-only: list findings with `file:line` and do not edit anything unless the user asks. Work through the five steps in order — each one narrows what the next has to look at, which is what keeps the review quick.

## 1. Scope

An explicit argument wins. Otherwise review everything the branch changed, which takes three commands because each one alone misses work:

- `git diff develop...HEAD` — committed on the branch (skip on `develop` itself);
- `git diff HEAD` — staged and unstaged;
- `git status --porcelain` — untracked files.

State the scope you reviewed in one line. If it is empty, say so and stop — don't fall back to reviewing the whole repository.

Judge only what the diff adds or changes. Pre-existing code is out of scope, including the template legacy documented in `.claude/rules/security.md` and `.claude/rules/architecture.md` (e.g. `UserId` in `Todos/Create`, `CreateTodoCommandValidator` as a `public class`): touching a line next to legacy is not a finding, but **new** code copying the legacy is.

## 2. Mechanical checks

When the scope touches `app/`, run these before reading the code:

1. `dotnet build CleanArchitecture.slnx` — analyzers run as errors, so this also catches style and nullability.
2. `dotnet test app/tests/Application.UnitTests`.

3. `dotnet test app/tests/IntegrationTests` — the downstream is faked by WireMock.Net, so no Docker is needed.

If `IntegrationTests` could not run, list them under "Not verified" — they include `EndpointAuthorizationTests` and `OpenApiDocumentTests`, so endpoint authorization and the OpenAPI contract must then be checked by reading.

A failing step is a finding, not a reason to stop: report it and keep reviewing.

## 3. Triage

Map the changed files to the checklist sections and skip sections with nothing in scope:

| Changed | Sections |
|---|---|
| `app/src/Domain/` | Layers, Domain model, Tests |
| `app/src/Application/` | Layers, Slice, Errors, Validation & ownership, State, C#, Observability, Tests |
| `app/src/Api/Controllers/` | Endpoint, Tests |
| `app/src/Infrastructure/` (repositories, services) | Layers, Persistence |
| `Directory.Packages.props`, `*.csproj` | C# (packages) |
| a spec (`SPEC-NNNN` in the branch, commits, or tests) | Specs & vault |

## 4. Checklist

Each section names the rule that owns the convention; open it when an item needs detail or you're unsure. If an item here and its rule disagree, the rule wins — follow it and report the drift.

### Layers — `.claude/rules/architecture.md`
- Application never uses `Infrastructure.*`; data access only through `I{Entity}Repository` or `I{Servico}Service`.
- Controller actions only map request → command and match the result; no business logic.

### Domain model — `.claude/rules/architecture.md`
- `{ get; private set; }`, private parameterless constructor, static `Create(...)` for new instances and static `Restore(...)` for rehydration (used only by Infrastructure).
- Every state change is a business-named entity method that enforces the invariant and returns `Result` when it can fail. A handler assigning properties is a violation. No domain events.
- Non-deterministic values (time) come in as parameters; exceptions are specific types, never `Exception`/`ApplicationException`.

### Slice — `.claude/rules/architecture.md`
- `app/src/Application/{Feature}/{UseCase}/` mirrored by a `{UseCase}` action in `app/src/Api/Controllers/{Feature}Controller.cs`; names `{Verb}{Entity}Command`/`Get{X}Query`/`...Handler`/`...Validator`/`{X}Response`.
- Handlers `internal sealed`, primary constructor, `ICommandHandler<>`/`IQueryHandler<,>`; no MediatR, no manual DI registration.
- Reads map the entity into the slice's DTO, never return entities; lists return `PagedList<T>`, paged by the repository.
- No validation or logging the decorators already do (`Abstractions/Behaviors/ValidationDecorator.cs`, `LoggingDecorator.cs`); logic repeated across handlers goes to an entity method or feature helper.

### Errors — `AGENTS.md` §4
- Fail by returning the catalog error directly (`return TodoItemErrors.NotFound(id);`); propagate with `return result;` / `return result.Error;`. `Result.Failure(...)`/`Result.Failure<T>(...)` in a handler or entity is a violation.
- `{Entity}Errors` factories with `"{EntityPlural}.{Reason}"` codes and the right `ErrorType`.
- No exceptions or try/catch for expected failures.

### Validation & ownership — `.claude/rules/architecture.md`, `.claude/rules/security.md`
- A validator for every command and every query with input beyond the route id: length limits, `IsInEnum` for enums, bounded paging.
- Identity comes from `IUserContext.UserId`, never from the request; the handler passes it to the repository, and another user's resource returns `{Entity}Errors.NotFound` (404).
- Time via `IDateTimeProvider` — no `DateTime.UtcNow`/`DateTime.Now` in Application.

### Endpoint — `.claude/rules/architecture.md`, `.claude/rules/security.md`
- `public sealed` controller, `ControllerBase`, `[ApiController]`, `[Route(...)]`; handler injected per action with `[FromServices]`.
- `[Authorize]` or `[Authorize(Policy = ...)]`; an intentionally anonymous action (`[AllowAnonymous]`) is justified and listed in `IntegrationTests/Api/EndpointAuthorizationTests.cs`.
- `[Tags(Tags.X)]`, `[EndpointSummary(...)]`, `[ProducesResponseType<T>(status)]` (or `[ProducesResponseType(204)]`), and `[ProducesResponseType<ProblemDetails>(status)]` per handler error — without repeating the 401/403/429/idempotency responses the transformers add.
- `result.Match(Results.Ok|Created|NoContent, CustomResults.Problem)`; a creating POST answers `201 Created` with the idempotency action filter.

### State — `.claude/rules/architecture.md`
- Mutation through the entity method, failure propagated, then the repository write (`AddAsync`/`UpdateAsync`/`DeleteAsync`) with its `Result` propagated.

### C# — `.claude/rules/csharp.md`
- Async end to end: the received `CancellationToken` reaches the last call (not `CancellationToken.None`/`default`); no `.Result`/`.Wait()`/`async void`.
- Package versions only in `Directory.Packages.props`; a new package is justified (ADR if structural); no LLM/AI package anywhere.

### Observability & personal data — `.claude/rules/observability.md`, `.claude/rules/security.md`
- Structured log templates; no personal data (names, e-mails, user-provided free text such as a todo description), tokens, or connection strings in logs, traces, metric tags, or error messages.
- Metrics named `app.<context>.<measure>` with low-cardinality tags, registered with `.AddMeter(...)`/`.AddSource(...)` in `Api/Extensions/OpenTelemetryExtensions.cs`.

### Persistence — `.claude/rules/persistence.md`
- Repository/service methods return `Result`/`Result<T>`; downstream 404 → `{Entity}Errors.NotFound`, failure/timeout → the catalog's `Failure` error; downstream body, raw status, or message never reach the caller.
- Typed `HttpClient` with base address from configuration; `CancellationToken` passed to every call; transport DTO → entity only through `Restore(...)`.

### Tests — `.claude/rules/testing.md`
- Handler: happy path (entity state + repository write received) and every failure path, with the repository substituted.
- Entity method: `{Entity}Tests` for success and each failure; state built through factory + methods.
- Validator: `TestValidate` per rule. Endpoint: integration test over real HTTP with the downstream faked by WireMock.Net. Naming and Arrange/Act/Assert match the neighbors.

### Specs & vault — `.claude/rules/specs.md`, `.claude/rules/docs-vault.md`
- New dependency/pattern/technology → ADR; new or renamed signal → `docs/03-Architecture/Observability.md`; new domain term → `docs/01-Product/Glossary.md`.

## 5. Report

Classify by impact, not by section:

- **Blockers** — must change before committing: failing build or unit tests; layer violation; endpoint without authorization; identity taken from the request or missing ownership filter; personal data, tokens, or secrets in logs or errors; exception for an expected failure; AI package.
- **Convention violations** — everything else in the checklist (naming, structure, `Result.Failure`, missing event, missing validation rule, incomplete OpenAPI contract…).
- **Test gaps** — missing tests per the Tests and Specs sections.

One line per finding: `file:line` — what's wrong → one-line fix (owning rule). Then:

- **Verification**: each command run and its result.
- **Not verified**: what was skipped and why (e.g. `IntegrationTests` without Docker).
- **Verdict**: ready to commit, or the list of what must change first.
