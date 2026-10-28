#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) — protege segredos e dados locais.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

while IFS= read -r raw; do
  [[ -z "$raw" ]] && continue
  rel="$(relpath "$raw")"

  # Segredos, certificados e estado local
  case "$rel" in
    .env.example|*/.env.example) ;;
    .env|.env.*|*/.env|*/.env.*) block "Edição de '$rel' bloqueada: segredos não são gerenciados por agentes (use dotnet user-secrets)." ;;
    *.pfx|*.pem|*.key|*.p12|*/secrets/*|secrets/*|*/secrets.json|secrets.json) block "Edição de '$rel' bloqueada (segredo/certificado)." ;;
    .git/*|*/.git/*) block "Edição direta em .git é proibida." ;;
    .containers/*) block "'.containers/' guarda os dados locais dos containers do compose — não é editável por agentes." ;;
  esac
done < <(touched_paths | sort -u)

exit 0
