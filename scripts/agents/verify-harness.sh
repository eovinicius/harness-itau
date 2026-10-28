#!/usr/bin/env bash
# Testes dos hooks do Agent Harness: expect <exit> <hook> <payload> <rótulo>. Sai com 1 se algum caso falhar.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
HOOKS="$ROOT/.claude/hooks"
fails=0

expect() {
  local want="$1" hook="$2" payload="$3" label="$4" got
  printf '%s' "$payload" | bash "$HOOKS/$hook" >/dev/null 2>&1
  got=$?
  if [[ "$got" == "$want" ]]; then printf 'ok   %s\n' "$label"
  else printf 'FAIL %s (exit %s, esperado %s)\n' "$label" "$got" "$want"; fails=$((fails + 1))
  fi
}

check() {
  local label="$1"; shift
  if "$@"; then printf 'ok   %s\n' "$label"
  else printf 'FAIL %s\n' "$label"; fails=$((fails + 1))
  fi
}

# --- format-dotnet.sh ---------------------------------------------------------
project="$(mktemp -d)"
export CLAUDE_PROJECT_DIR="$project"
session="verify-harness-$$"
queue="${TMPDIR:-/tmp}/claude-format-dotnet-$session.txt"
trap 'rm -rf "$project" "$queue"' EXIT

mkdir -p "$project/src" "$project/src/obj"
printf 'root = true\n[*.cs]\nindent_style = space\nindent_size = 4\n' >"$project/.editorconfig"
printf 'namespace X;\npublic class A\n{\n        public int B { get; set; }\n}\n' >"$project/src/A.cs"

post() { printf '{"session_id":"%s","hook_event_name":"PostToolUse","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$session" "$1"; }
stop() { printf '{"session_id":"%s","hook_event_name":"Stop"}' "$session"; }

expect 0 format-dotnet.sh "$(stop)" "format-dotnet: Stop sem fila"
expect 0 format-dotnet.sh "$(post "$project/README.md")" "format-dotnet: ignora arquivo não .cs"
expect 0 format-dotnet.sh "$(post "$project/src/obj/Gen.cs")" "format-dotnet: ignora .cs em obj/"
check "format-dotnet: fila vazia para não .cs" test ! -s "$queue"
expect 0 format-dotnet.sh "$(post "$project/src/A.cs")" "format-dotnet: enfileira .cs"
check "format-dotnet: fila contém src/A.cs" grep -qx 'src/A.cs' "$queue"
check "format-dotnet: PostToolUse não reescreve o arquivo" grep -q '^        public int B' "$project/src/A.cs"

if command -v dotnet >/dev/null 2>&1; then
  expect 0 format-dotnet.sh "$(stop)" "format-dotnet: Stop formata a fila"
  check "format-dotnet: indentação corrigida" grep -q '^    public int B' "$project/src/A.cs"
  check "format-dotnet: fila removida após Stop" test ! -e "$queue"
else
  printf 'skip format-dotnet: Stop (dotnet ausente)\n'
fi

(( fails == 0 )) || { printf '\n%s caso(s) falharam.\n' "$fails"; exit 1; }
printf '\nTodos os casos passaram.\n'
