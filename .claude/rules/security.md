# Segurança e LGPD (sempre carregada)

## Autenticação e autorização

- **AuthN**: JWT + refresh tokens com rotação (Infrastructure/Authentication). Não altere o fluxo de tokens sem pedido explícito.
- **AuthZ**: todo controller novo declara `[Authorize]`; permissão específica na action com `[Authorize(Policy = "<recurso>:<ação>")]`.
- **Anônimo** (`[AllowAnonymous]`) só se intencional e justificado no PR — e entra na lista de `IntegrationTests/Api/EndpointAuthorizationTests.cs`, que quebra com endpoint sem autorização.

## Propriedade do recurso (padrão único)

- A identidade vem **sempre** de `IUserContext.UserId` (token), nunca do payload.
- Recurso de outro usuário ⇒ o repository filtra por `UserId` e o handler retorna `{Entity}Errors.NotFound` (**404**, não revela que o recurso existe). Modelo: `Application/Todos/GetById/`.
- **Legado do template, não replique**: `Todos/Create`, `Todos/Copy`, `Todos/Get` e `Users/GetById` recebem `UserId` no request e respondem 403 `UserErrors.Unauthorized()`.

## Entrada e controles

- **Entrada**: toda entrada externa tem validator FluentValidation com limites de tamanho.
- **Downstream**: segmentos de rota e query string codificados (`Uri.EscapeDataString`) — nunca concatenação de entrada crua.
- **Controles existentes** (rate limiting, security headers, CORS, idempotência, hashing de senha, `GlobalExceptionHandler`) não são afrouxados sem pedido explícito.
- Nunca exponha stack trace ou mensagem interna ao cliente.

## Segredos e LGPD

- **Segredos**: `dotnet user-secrets` local (o compose monta `UserSecrets`); nada real em `appsettings*.json`, código, testes, logs, docs ou prompts. Os hooks bloqueiam `.env`, `*.pfx`, `*.pem`, `secrets/`.
- **LGPD**: dados de usuários (nome, e-mail, telefone) e conteúdo livre que eles informam (ex.: descrição de tarefa) são dados pessoais.
  - Fora de logs, traces, tags de métrica e mensagens de erro.
  - Respostas devolvem só o necessário.

## Dependências e revisão

- **Dependências**: pacote novo exige justificativa; preferir libs mantidas e licença permissiva; `dotnet list package --vulnerable` antes do PR. Pacotes de IA proibidos (core #2).
- **Revisão dedicada**: subagente `security-reviewer` quando o diff tocar auth, entrada de dados, logs, config ou dependências.
