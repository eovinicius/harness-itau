---
paths:
  - "app/tests/**"
  - "app/src/**"
---
# Testes

Stack real: **xUnit 2.9 + Shouldly + NSubstitute**; WireMock.Net (simula o downstream) + `Microsoft.AspNetCore.Mvc.Testing` para integração.

| Projeto | O que cobre | Infra |
| --- | --- | --- |
| `app/tests/Application.UnitTests` | Handlers (happy path + **cada** `Result.Failure`), validators (`TestValidate` por regra), decorators | nenhuma |
| `app/tests/IntegrationTests` | HTTP real via `IntegrationTestWebAppFactory` + `BaseIntegrationTest`, downstream simulado pelo WireMock.Net | nenhuma (in-process) |

- Nome: `Metodo_Should_Resultado_WhenCondicao` (ex.: `Handle_Should_ReturnNotFound_WhenTodoDoesNotExist`). Arrange/Act/Assert.
- Imite a classe de teste vizinha mais parecida (helpers, doubles, asserções). Ex.: `Application.UnitTests/Todos/`.
- Verifique o estado da entidade e os efeitos colaterais (escrita no repository, chamada ao downstream), não só o retorno.
- **Entidade**: `{Entity}Tests` em `Application.UnitTests/{Feature}/` (modelo: `Application.UnitTests/Todos/TodoItemTests.cs`) cobre cada método de comportamento — sucesso e cada `Result.Failure`.
- **Seed** pela factory e pelos métodos da entidade (`TodoItem.Create(...)`, depois `.Complete(...)`/`.Archive(...)` para chegar ao estado), ou `Restore(...)` para um estado vindo do downstream que os métodos não alcançam. Nunca reflection nem setter aberto para montar estado; id gerado é capturado da entidade (`user.Id`), não fixado.
- Testes isolados: dados únicos por teste, sem dependência de ordem.
- `IntegrationTests/Api/OpenApiDocumentTests.cs` deve continuar verde — é o guarda do contrato HTTP.
- **Bug**: primeiro um teste que reproduz (vermelho), depois a correção.
- Comandos: `dotnet test app/tests/Application.UnitTests` · `dotnet test CleanArchitecture.slnx`. Não rodou? Diga no relatório em vez de declarar sucesso.
