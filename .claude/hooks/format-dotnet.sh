#!/usr/bin/env bash
# Formata os .cs editados pelo agente segundo o .editorconfig. O CI roda 'dotnet format --verify-no-changes'. Nunca bloqueia.
#   PostToolUse(Edit|Write) — só enfileira o caminho (barato; não reescreve o arquivo no meio da tarefa).
#   Stop                    — formata a fila de uma vez: whitespace (--folder, sem build) + style (carrega a solução).
# Falha de formatação vira aviso ao usuário (systemMessage), sem bloquear. Analyzers ficam com o CI.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

session="$(json_get '.session_id' | tr -cd 'A-Za-z0-9_-')"
queue="${TMPDIR:-/tmp}/claude-format-dotnet-${session:-default}.txt"

# Orçamento interno (30 + 75 s) abaixo do timeout de 120 s do hook Stop em .claude/settings.json.
WHITESPACE_TIMEOUT=30
STYLE_TIMEOUT=75

# timeout do coreutils: no Git Bash evita o timeout.exe do Windows; no macOS pode faltar (gtimeout via Homebrew).
with_timeout() {
  local secs="$1"; shift
  if [[ -x /usr/bin/timeout ]]; then /usr/bin/timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  else "$@"
  fi
}

warn_user() {
  printf '{"systemMessage":"%s"}\n' "$(json_escape "[harness] $1")"
  exit 0
}

if [[ "$(json_get '.hook_event_name')" != "Stop" ]]; then
  raw="$(touched_paths)"
  [[ -n "$raw" ]] || exit 0
  rel="$(relpath "$raw")"
  [[ "$rel" == *.cs && "$rel" != */obj/* && "$rel" != */bin/* ]] && printf '%s\n' "$rel" >>"$queue"
  exit 0
fi

[[ -f "$queue" ]] || exit 0
command -v dotnet >/dev/null 2>&1 || { rm -f "$queue"; exit 0; }

files=()
while IFS= read -r rel; do
  [[ -f "$HOOK_PROJECT_DIR/$rel" ]] && files+=("$rel")
done < <(sort -u "$queue")
rm -f "$queue"
[[ ${#files[@]} -eq 0 ]] && exit 0

cd "$HOOK_PROJECT_DIR" || exit 0
failed=""

with_timeout "$WHITESPACE_TIMEOUT" dotnet format whitespace --folder --include "${files[@]}" >/dev/null 2>&1 \
  || failed+=" whitespace"

# style precisa do workspace restaurado; --no-restore evita disputar obj/ com o build do stop-verify.sh, que roda em paralelo.
if [[ -f CleanArchitecture.slnx ]]; then
  with_timeout "$STYLE_TIMEOUT" dotnet format style CleanArchitecture.slnx --no-restore --include "${files[@]}" >/dev/null 2>&1 \
    || failed+=" style"
fi

[[ -n "$failed" ]] && warn_user "dotnet format falhou ou excedeu o tempo (${failed# }) em ${#files[@]} arquivo(s). Rode 'dotnet format CleanArchitecture.slnx' antes do push."
exit 0
