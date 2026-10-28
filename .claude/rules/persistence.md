---
paths:
  - "app/src/Infrastructure/**"
  - "app/src/Application/**"
---
# Persistência (sem banco próprio)

O projeto não tem banco nem migrations. Os dados pertencem a APIs externas, acessadas por repository ou service. Skill: `add-entity`.

- **Interfaces na Application**: `I{Entity}Repository` (dados de uma entidade) ou `I{Servico}Service` (operação de um serviço externo), em `Application/Abstractions/` (ou na pasta da feature quando só ela usa).
- **Implementação na Infrastructure** (`Infrastructure/{Feature}/`), com typed `HttpClient` registrado por `AddHttpClient<I{Entity}Repository, {Entity}Repository>` e base address vindo de configuração.
- **Retorno sempre `Result`/`Result<T>`.** A implementação traduz falhas do downstream para o catálogo `{Entity}Errors`: 404 ⇒ `NotFound(id)`; indisponibilidade/timeout ⇒ erro `Failure` do catálogo. Nunca repasse corpo, status bruto ou mensagem do downstream ao consumidor.
- **Propriedade do recurso**: o repository recebe o `userId` (vindo de `IUserContext` no handler) e devolve `NotFound` para recurso de outro usuário (`security.md`).
- **Escrita** por método do repository (`AddAsync`, `UpdateAsync`, `DeleteAsync`), chamado pelo handler depois do método da entidade.
- **Listas**: o repository recebe filtro, ordenação e `page`/`pageSize`, repassa ao downstream e devolve `PagedList<{Entity}>`.
- **Reidratação**: o DTO de transporte (na Application, reusado pela Infrastructure — `architecture.md`) vira entidade só por `{Entity}.Restore(...)` (`architecture.md`, Domain). **Nunca** abra setter público para mapear.
- `CancellationToken` repassado em toda chamada HTTP.
