#!/usr/bin/env bash
# PreToolUse(Edit|Write|NotebookEdit) — protege segredos, dados locais e ADRs aceitos.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

while IFS= read -r raw; do
  [[ -z "$raw" ]] && continue
  rel="$(relpath "$raw")"
  base="$(basename "$rel")"

  # Segredos, certificados e estado local
  case "$rel" in
    .env.example|*/.env.example) ;;
    .env|.env.*|*/.env|*/.env.*) block "Edição de '$rel' bloqueada: segredos não são gerenciados por agentes (use dotnet user-secrets)." ;;
    *.pfx|*.pem|*.key|*.p12|*/secrets/*|secrets/*|*/secrets.json|secrets.json) block "Edição de '$rel' bloqueada (segredo/certificado)." ;;
    .git/*|*/.git/*) block "Edição direta em .git é proibida." ;;
    .containers/*) block "'.containers/' guarda os dados locais dos containers do compose — não é editável por agentes." ;;
  esac

  # ADR aceita é imutável — só status/superseded_by, com confirmação humana
  if [[ "$rel" == docs/04-ADRs/ADR-*.md && -f "$HOOK_PROJECT_DIR/$rel" ]] && grep -qE '^status: *Accepted' "$HOOK_PROJECT_DIR/$rel"; then
    ask_user "A ADR '$base' está Accepted (imutável). Só altere status/superseded_by ao substituí-la por uma nova ADR. Confirmar a edição?"
  fi
done < <(touched_paths | sort -u)

exit 0
