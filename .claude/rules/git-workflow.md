# Git e Pull Requests (sempre carregada)

**Fluxo com branch única de trabalho: `feature/*`.**

| Branch | Sai de | PR para |
| --- | --- | --- |
| `feature/<id-da-historia>-<titulo-curto>` | `develop` | `develop` |

- **Nome da branch**: `feature/` + ID da história do card + `-` + título curto, com as palavras do título separadas por `-` (minúsculas, sem acento nem espaço). Sem o ID do card, pergunte ao usuário — não invente.
- **Toda mudança usa `feature/*`** — feature, correção de bug, ajuste de release ou correção urgente. Não crie branch com outro prefixo.
- **Base atualizada antes de criar a branch**: `git switch develop && git pull --ff-only && git switch -c feature/<id-da-historia>-<titulo-curto>`. Working tree sujo ou `pull` que não é fast-forward ⇒ pare e avise o usuário; não faça stash, merge nem rebase por conta própria.
- **Nunca** push direto ou force em `main`/`develop` (hook `guard-shell.sh` bloqueia). Tudo entra por PR com CI verde.
- **PR é aberto pela pipeline**: o push da `feature/*` dispara a pipeline, que cria o PR automaticamente — não abra PR (`gh pr create`). Acompanhe com o subagente `ci-watcher`.
  - **Verde** ⇒ preencha a descrição do PR que a pipeline criou (`gh pr edit <n> --body-file <arquivo>`), com o conteúdo do item "PR descreve" abaixo.
  - **Vermelho** ⇒ não preencha a descrição; diagnostique, corrija na mesma branch e acompanhe de novo.
- Proibido: `--no-verify`, `git reset --hard`, `git clean -f` pelo agente (o usuário executa manualmente se quiser).
- **Mensagem de commit** (quando e idioma: core #8 e #9): `feat(todos): adiciona arquivamento de tarefas (SPEC-0001)`. Referencie a SPEC quando houver.
- PR descreve: spec relacionada, mudança de contrato HTTP (sim/não; breaking?), como foi testado (comandos + resultado), riscos e rollback.
- Não commite artefatos: `bin/`, `obj/`, `.containers/`, `TestResults/`, `.claude/settings.local.json`.
