#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/soul-common.sh
. "${SCRIPT_DIR}/soul-common.sh"

soul_load_env

default_base="${SOUL_OPENAI_BASE_URL:-http://127.0.0.1:11434/v1}"
default_model="${SOUL_OLLAMA_MODEL:-${SOUL_MODEL_ALIAS:-qwen3:8b}}"

printf 'Soul/ Ollama setup\n'
printf '\n'

if ! soul_have ollama; then
  soul_fail "ollama command not found. Install Ollama first, then re-run make setup-ollama."
fi

if [ -f "$SOUL_ENV_FILE" ] && [ "${SOUL_RUNTIME_PROVIDER:-}" = "ollama" ] && [ -n "${SOUL_OPENAI_BASE_URL:-}" ]; then
  if soul_endpoint_models_ok "$SOUL_OPENAI_BASE_URL"; then
    printf 'Existing Ollama configuration appears reachable:\n'
    printf '  %s\n' "$SOUL_OPENAI_BASE_URL"
    if ! soul_confirm_default_no "Reconfigure Ollama anyway?"; then
      printf 'Leaving existing configuration unchanged.\n'
      exit 0
    fi
  fi
fi

base_url="$(soul_prompt_default "Ollama OpenAI-compatible base URL" "$default_base")"
model="$(soul_prompt_default "Ollama model name" "$default_model")"

printf '\nChecking locally available Ollama models...\n'
if ollama list 2>/dev/null | awk 'NR > 1 {print $1}' | grep -Fxq "$model"; then
  printf 'OK: Ollama model already installed: %s\n' "$model"
else
  printf 'Model not found locally: %s\n' "$model"
  if soul_confirm_default_yes "Pull it with ollama pull?"; then
    ollama pull "$model"
  else
    soul_warn "Skipping model pull. Runtime test may fail if the model is unavailable."
  fi
fi

printf '\nChecking Ollama endpoint: %s/models\n' "${base_url%/}"
if ! soul_endpoint_models_ok "$base_url"; then
  soul_warn "Could not reach ${base_url%/}/models."
  soul_warn "Make sure the Ollama service is running."
else
  printf 'OK: Ollama OpenAI-compatible endpoint is reachable.\n'
fi

soul_backup_env_if_exists
soul_write_env_ollama "$base_url" "$model"

printf '\nWrote %s\n' "$SOUL_ENV_FILE"
printf '\nNext steps:\n'
printf '  make test-runtime\n'
