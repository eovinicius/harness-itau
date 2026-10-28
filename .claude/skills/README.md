# Agent Skills

Procedures that teach Claude Code this repository's conventions: vertical-slice use cases, custom command/query handlers (no MediatR), Result-based error handling, controller-based endpoints, and full test coverage. Claude picks a skill automatically from its `description`; you can also invoke it explicitly.

## Template skills

| Skill | Invoke with | What it does |
|---|---|---|
| **add-feature** | `/add-feature archive a todo item` | Scaffolds a complete vertical slice: command/query, handler, validator, endpoint, and unit + validator + integration tests. |
| **add-entity** | `/add-entity Project with a name and owner` | Adds a domain entity end to end: entity, error catalog, repository interface, downstream HTTP implementation. |
| **add-tests** | `/add-tests CopyTodoCommand` | Backfills handler, validator, and integration tests for existing use cases. |
| **add-background-job** | `/add-background-job delete expired refresh tokens hourly` | Adds a scheduled `BackgroundService` that runs an Application command in a per-iteration scope. |
| **bootstrap** | `/bootstrap Acme.Billing` | Renames the solution to your app and strips the sample Todos feature (keeps Users + auth). |
| **ca-review** | `/ca-review` | Quick inline convention checklist. For the full pre-PR review, use `/review`. |

## Harness skills (pt-BR)

| Skill | Invoke with | What it does |
|---|---|---|
| **write-spec** | `/write-spec arquivar tarefas concluídas` | Writes/evolves a spec in the Obsidian vault (`docs/02-Specs`) with testable acceptance criteria; reviewed by the `spec-reviewer` subagent. |
| **implement-spec** | `/implement-spec SPEC-0001` | Implements an `Approved` spec AC by AC (red test → domain → slice → endpoint → repository), then verifies and closes the spec. |
| **create-rule** | `/create-rule feature flags nos controllers` | Creates or evolves a rule in `.claude/rules/` with a single owner per convention, the right load scope (`paths:`), and verifiable bullets. |
| **dependency-upgrade** | `/dependency-upgrade OpenTelemetry` | Safe NuGet upgrades through Central Package Management, with real versions from the `nuget` MCP. |
| **instrument-observability** | `/instrument-observability todos completed per priority` | Adds metrics/spans/logs following the Serilog + dd-trace-dotnet setup exported to Datadog. |
| **investigate-issue** | `/investigate-issue 500 on POST /todos` | Reproduces locally and correlates Datadog evidence (Logs, APM) until a probable cause is found. |

The rest of the harness (rules, subagents, hooks, MCP) is documented in `docs/05-Engineering/Agent-Harness.md`.

Each skill is a plain Markdown file (`SKILL.md`, plus templates under `references/`). Changing a convention? Edit the skill once (and the matching rule in `.claude/rules/`), then run `bash scripts/agents/verify-harness.sh`.
