---
paths:
  - "**/*.cs"
  - "**/*.csproj"
  - "Directory.*.props"
  - ".editorconfig"
---
# C# 14 / .NET 10

O build é o lint: `Directory.Build.props` liga os analisadores e trata warning como erro (flags no próprio arquivo). Warning = build quebrado.

## Build e formatação

- **Corrija o warning, não suprima.** `#pragma warning disable` ou `[SuppressMessage]` só com justificativa no código. Mexer em `NoWarn`, `.editorconfig` ou `Directory.Build.props` para silenciar regra exige pedido explícito.
- Siga o `.editorconfig`: file-scoped namespaces, estilo de `var`, chaves, ordem de usings.
- O hook `format-dotnet.sh` formata os `.cs` editados ao fim do turno. Antes de concluir, rode `dotnet format CleanArchitecture.slnx --verify-no-changes` (o CI roda o mesmo).

## Estilo

- Em código novo ou alterado, prefira: primary constructors para DI, collection expressions (`[]`, `[.. x]`), `record` para DTOs, pattern matching/switch expressions; do C# 14, propriedade com `field`, blocos `extension` e `?.=` quando simplificarem.
- Dúvida sobre sintaxe ou semântica do C# 14? Consulte antes de usar — MCP `microsoft-learn` ou [What's new in C# 14](https://learn.microsoft.com/en-us/dotnet/csharp/whats-new/csharp-14). Não chute.
- Não converta legado fora do escopo (core #5).
- Comparações de cultura invariável (`ToUpperInvariant`, `StringComparison.Ordinal*`).
- Comente pouco: só o *porquê* não óbvio. Siga a densidade de comentários do arquivo.

## Tipos e visibilidade

- `Nullable` habilitado: modele a nulidade, não silencie com `!`.
- Visibilidade mínima: `internal sealed` por padrão; `public` só o que é contrato ou o framework exige. Classe de teste é `public sealed`: o xUnit só descobre classe pública.
- **`sealed` em toda classe e record concretos** (inclusive `public`, middleware, DTO, nested e classe de teste), salvo quando projetados para herança — base `abstract` ou com subclasse real (ex.: `Result`, `Error`).

## Async

- Async de ponta a ponta: sufixo `Async`; o `CancellationToken` recebido chega até a última chamada (nunca `CancellationToken.None`/`default`).
- Nunca `.Result`/`.Wait()`/`GetAwaiter().GetResult()`/`async void`.
- Não use `Task.Run` para embrulhar I/O síncrono. Toda `Task` é aguardada (sem fire-and-forget); trabalho em segundo plano vai para um `BackgroundService`.

## Erros e logging

- Falha esperada de negócio é `Error`/`Result` (`architecture.md`), não exceção.
- Não capture `Exception` genérico fora de fronteiras (handler global, background job).
- Lance tipo específico (existente ou novo, ex.: `UserContextUnavailableException`), nunca `Exception`/`ApplicationException` genéricos.
- Logging: Serilog/`ILogger` com templates estruturados (`{TodoId}`), nunca interpolação. Dados pessoais em log: `security.md`.

## Pacotes

- **Central Package Management**: versão só em `Directory.Packages.props`; no `.csproj`, `<PackageReference Include="X" />` sem `Version`.
- Não use `dotnet add package --version`.
