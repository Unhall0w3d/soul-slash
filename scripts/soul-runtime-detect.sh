#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/soul-common.sh
. "${SCRIPT_DIR}/soul-common.sh"

mode="${1:-}"

soul_load_env

llama_bin=""
if soul_have llama-server; then
  llama_bin="$(command -v llama-server)"
elif [ -n "${SOUL_LLAMA_SERVER:-}" ] && [ -x "${SOUL_LLAMA_SERVER}" ]; then
  llama_bin="${SOUL_LLAMA_SERVER}"
fi

ollama_bin=""
if soul_have ollama; then
  ollama_bin="$(command -v ollama)"
fi

printf 'Soul/ runtime detection\n'
printf '\n'

printf 'Runtime binaries:\n'
if [ -n "$llama_bin" ]; then
  printf '  OK      llama.cpp: %s\n' "$llama_bin"
else
  printf '  missing llama.cpp: llama-server not found\n'
fi

if [ -n "$ollama_bin" ]; then
  printf '  OK      Ollama: %s\n' "$ollama_bin"
else
  printf '  missing Ollama: ollama not found\n'
fi

printf '\nOpenAI-compatible /v1 endpoint probes:\n'
probe_v1_ports=(8080 8081 8082 8083 8084 8085 8000 5000 11434)
reachable_v1=()
for port in "${probe_v1_ports[@]}"; do
  url="http://127.0.0.1:${port}/v1"
  if soul_endpoint_models_ok "$url"; then
    printf '  OK      %-28s %s/models\n' "port ${port}" "$url"
    reachable_v1+=("$url")
  else
    printf '  missing %-28s %s/models\n' "port ${port}" "$url"
  fi
done

printf '\nProvider-native endpoint probes:\n'
if soul_http_ok "http://127.0.0.1:8082/health"; then
  printf '  OK      llama.cpp health        http://127.0.0.1:8082/health\n'
else
  printf '  missing llama.cpp health        http://127.0.0.1:8082/health\n'
fi

if soul_ollama_native_ok "http://127.0.0.1:11434"; then
  printf '  OK      Ollama native API       http://127.0.0.1:11434/api/tags\n'
else
  printf '  missing Ollama native API       http://127.0.0.1:11434/api/tags\n'
fi

printf '\nNote: llama.cpp and Ollama OpenAI compatibility use /v1. Ollama also has native /api endpoints. No /v2 runtime API is assumed.\n'

printf '\nCurrent config:\n'
if [ -f "$SOUL_ENV_FILE" ]; then
  printf '  OK      %s\n' "$SOUL_ENV_FILE"
  printf '  provider: %s\n' "${SOUL_RUNTIME_PROVIDER:-unset}"
  printf '  base URL: %s\n' "${SOUL_OPENAI_BASE_URL:-unset}"
  printf '  model:    %s\n' "${SOUL_MODEL_ALIAS:-unset}"

  if [ -n "${SOUL_OPENAI_BASE_URL:-}" ]; then
    if soul_endpoint_models_ok "$SOUL_OPENAI_BASE_URL"; then
      printf '  endpoint: reachable\n'
    else
      printf '  endpoint: not reachable\n'
    fi
  fi
else
  printf '  missing %s\n' "$SOUL_ENV_FILE"
fi

printf '\nLocal GGUF model discovery:\n'
mapfile -t gguf_files < <(soul_find_gguf_files)
if [ "${#gguf_files[@]}" -eq 0 ]; then
  printf '  none found in ./models or ~/Downloads\n'
else
  i=1
  for file in "${gguf_files[@]}"; do
    [ "$i" -le 20 ] || { printf '  ... showing first 20 only\n'; break; }
    if soul_validate_gguf "$file"; then
      printf '  OK      %s\n' "$file"
    else
      printf '  invalid %s\n' "$file"
    fi
    i=$((i + 1))
  done
fi

if [ "$mode" = "--setup" ]; then
  printf '\nSetup choices:\n'
  printf '  1) llama.cpp server\n'
  printf '  2) Ollama\n'
  printf '\n'

  if [ -f "$SOUL_ENV_FILE" ] && [ -n "${SOUL_RUNTIME_PROVIDER:-}" ] && [ -n "${SOUL_OPENAI_BASE_URL:-}" ]; then
    if soul_endpoint_models_ok "$SOUL_OPENAI_BASE_URL"; then
      printf 'Existing .env runtime appears reachable:\n'
      printf '  provider: %s\n' "$SOUL_RUNTIME_PROVIDER"
      printf '  base URL: %s\n' "$SOUL_OPENAI_BASE_URL"
      if ! soul_confirm_default_no "Reconfigure anyway?"; then
        printf 'Leaving existing runtime configuration unchanged.\n'
        exit 0
      fi
    fi
  fi

  if [ -n "$llama_bin" ] && [ -z "$ollama_bin" ]; then
    default_choice="1"
  elif [ -z "$llama_bin" ] && [ -n "$ollama_bin" ]; then
    default_choice="2"
  else
    default_choice="1"
  fi

  choice="$(soul_prompt_default "Choose runtime provider" "$default_choice")"
  case "$choice" in
    1|llama|llamacpp|llama.cpp)
      exec "${SCRIPT_DIR}/soul-setup-llamacpp.sh"
      ;;
    2|ollama)
      exec "${SCRIPT_DIR}/soul-setup-ollama.sh"
      ;;
    *)
      soul_fail "Unknown setup choice: $choice"
      ;;
  esac
fi
