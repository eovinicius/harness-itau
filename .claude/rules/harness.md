---
paths:
  - ".claude/**"
  - "scripts/agents/**"
  - ".mcp.json"
  - "AGENTS.md"
  - "CLAUDE.md"
---
# Manutenção do Agent Harness

Mapa e princípios: `docs/05-Engineering/Agent-Harness.md`.

## Hooks

- **Hook alterado ⇒ caso de teste** em `scripts/agents/verify-harness.sh` (`expect <exit> <hook> <payload> <rótulo>`):
  - Bloqueio novo ganha um `expect 2`.
  - O comando legítimo vizinho ganha um `expect 0`, para pegar falso positivo.
  - Regra que depende da branch usa o repositório temporário em `develop` do próprio script.
- **Portáveis** (Git Bash no Windows, bash no Linux/macOS): sem `sed` com flag `I`, sem `\n` na substituição do `sed`, caminhos via `relpath`/`to_posix` do `lib.sh`.
- **Contrato de saída**: `0` segue, `2` bloqueia (stderr volta ao agente); erro de leitura da entrada **bloqueia**, não libera.

## Configuração

- **Permissões simétricas**: toda regra `Bash(...)` em `.claude/settings.json` tem a equivalente `PowerShell(...)`.
- **MCP**: `.mcp.json` só tem servidor sem segredo, com versão fixada; servidor com chave vai para o escopo `local` de cada dev (documentado em `Agent-Harness.md`).

## Rules, skills e agents

- **Um dono por convenção.** Convenção mudou? Atualize **um** dono (rule ou skill) e, se for invariante, a linha do `AGENTS.md`. Não duplique texto entre arquivos.
  - Propriedade do recurso e legado do template → `security.md`.
  - Slice, validator e contrato de endpoint → `architecture.md`.
  - Skills e agents apontam para o dono em vez de repetir a regra.
- **Caminhos citados** em `code` nas rules, skills e agents precisam existir: o `verify-harness.sh` checa. Arquivo a ser criado usa placeholder (`{Feature}`), não um nome concreto.
- **Idioma das skills**: skill nova segue o grupo a que pertence.
  - Template (`add-*`, `ca-review`, `bootstrap`): inglês, para continuarem reaproveitáveis fora deste repositório.
  - Harness/SDD (`write-spec`, `implement-spec`…) e agents: pt-BR, como o vault.
- **Subagente que não edita** registra `readonly-shell.sh` como hook `PreToolUse` de Bash no próprio frontmatter.
- **Skill com efeito destrutivo ou amplo** (ex.: `bootstrap`) leva `disable-model-invocation: true`: só roda por `/nome`.

## Verificação

- Antes de concluir: `bash scripts/agents/verify-harness.sh` com exit 0.
