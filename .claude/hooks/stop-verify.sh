#!/usr/bin/env bash
# Stop — se código .NET mudou, exige build (warnings já são erros) + testes unitários e de arquitetura antes de encerrar.
# IntegrationTests ficam de fora (Docker, lentos). Opt-out pontual: HARNESS_SKIP_STOP_VERIFY=1.
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
cd "$HOOK_PROJECT_DIR" || exit 0

[[ "${HARNESS_SKIP_STOP_VERIFY:-0}" == "1" ]] && exit 0
command -v dotnet >/dev/null 2>&1 || exit 0

changed="$( { git diff --name-only HEAD 2>/dev/null; git ls-files --others --exclude-standard 2>/dev/null; } \
  | grep -E '\.(cs|csproj|props|targets|slnx|editorconfig)$|(^|/)\.editorconfig$' | sort -u)"
[[ -z "$changed" ]] && exit 0

log="$(mktemp)"
trap 'rm -f "$log"' EXIT

# Orçamento total (240 + 2 × 150 s) abaixo do timeout de 600 s do hook em .claude/settings.json:
# se o Claude Code matar o hook, a parada passa sem verificação.
timeout 240 dotnet build CleanArchitecture.slnx --nologo -v quiet >"$log" 2>&1
status=$?
(( status == 124 )) && block "Build excedeu 240 s no hook Stop. Rode 'dotnet build CleanArchitecture.slnx' e confirme o resultado antes de concluir."
if (( status != 0 )); then
  block "Build falhou (warnings contam como erro). Corrija antes de concluir:
$(grep -E ': (error|warning|erro|aviso) ' "$log" | sed -E 's/ \[[^]]+\]$//' | sort -u | head -40)"
fi

for project in app/tests/Application.UnitTests; do
  [[ -d "$project" ]] || continue
  timeout 150 dotnet test "$project" --no-build --nologo -v quiet >"$log" 2>&1
  status=$?
  (( status == 124 )) && block "Testes de $project excederam 150 s no hook Stop. Rode 'dotnet test $project' e confirme o resultado antes de concluir."
  if (( status != 0 )); then
    block "Testes falharam em $project. Corrija antes de concluir (não enfraqueça nem pule testes):
$(grep -E 'Failed |Com falha|Falha |Error Message|Mensagem de erro|Shouldly|\[FAIL\]' "$log" | head -40)
$(tail -15 "$log")"
  fi
done

exit 0
