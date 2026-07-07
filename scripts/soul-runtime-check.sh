#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/soul-common.sh
. "${SCRIPT_DIR}/soul-common.sh"

printf 'Soul/ local tool check\n'
printf '\n'

missing=0

printf 'Required tools:\n'
for tool in ruby git make curl unzip; do
  if soul_have "$tool"; then
    printf '  OK      %-8s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  MISSING %-8s\n' "$tool"
    missing=1
  fi
done

printf '\nRecommended tools:\n'
for tool in jq zip python3 python; do
  if soul_have "$tool"; then
    printf '  OK      %-8s %s\n' "$tool" "$(command -v "$tool")"
  else
    printf '  missing %-8s\n' "$tool"
  fi
done

printf '\nRuntime tools:\n'
if soul_have llama-server; then
  printf '  found   llama.cpp server: %s\n' "$(command -v llama-server)"
else
  printf '  missing llama.cpp server: llama-server\n'
fi

if soul_have ollama; then
  printf '  found   Ollama: %s\n' "$(command -v ollama)"
else
  printf '  missing Ollama: ollama\n'
fi

printf '\nConfig:\n'
if [ -f "$SOUL_ENV_FILE" ]; then
  printf '  found   %s\n' "$SOUL_ENV_FILE"
else
  printf '  missing %s\n' "$SOUL_ENV_FILE"
  printf '          Run make setup, make setup-llamacpp, or make setup-ollama.\n'
fi

if [ "$missing" -ne 0 ]; then
  printf '\nCheck failed: missing required tools.\n'
  exit 1
fi

printf '\nCheck complete. For runtime endpoint discovery, run: make detect\n'
