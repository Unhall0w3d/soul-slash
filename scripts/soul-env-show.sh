#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/soul-common.sh
. "${SCRIPT_DIR}/soul-common.sh"

soul_load_env

printf 'Soul/ environment\n'
printf '  file:     %s\n' "$SOUL_ENV_FILE"
printf '  provider: %s\n' "${SOUL_RUNTIME_PROVIDER:-unset}"
printf '  base URL: %s\n' "${SOUL_OPENAI_BASE_URL:-unset}"
printf '  model:    %s\n' "${SOUL_MODEL_ALIAS:-unset}"
printf '\n'

case "${SOUL_RUNTIME_PROVIDER:-}" in
  llamacpp)
    printf 'llama.cpp\n'
    printf '  server:   %s\n' "${SOUL_LLAMA_SERVER:-llama-server}"
    printf '  dir:      %s\n' "${SOUL_MODEL_DIR:-./models}"
    printf '  file:     %s\n' "${SOUL_MODEL_FILE:-unset}"
    printf '  URL:      %s\n' "${SOUL_MODEL_URL:-unset}"
    ;;
  ollama)
    printf 'Ollama\n'
    printf '  model:    %s\n' "${SOUL_OLLAMA_MODEL:-${SOUL_MODEL_ALIAS:-unset}}"
    ;;
  *)
    printf 'No recognized provider configured.\n'
    ;;
esac
