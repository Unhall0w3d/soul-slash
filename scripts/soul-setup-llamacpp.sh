#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/soul-common.sh
. "${SCRIPT_DIR}/soul-common.sh"

download_only=false
if [ "${1:-}" = "--download-only" ]; then
  download_only=true
fi

soul_load_env

if [ -f "$SOUL_ENV_FILE" ] && [ "${SOUL_RUNTIME_PROVIDER:-}" = "llamacpp" ] && [ -n "${SOUL_OPENAI_BASE_URL:-}" ]; then
  if soul_endpoint_models_ok "$SOUL_OPENAI_BASE_URL"; then
    printf 'Existing llama.cpp configuration appears reachable:\n'
    printf '  %s\n' "$SOUL_OPENAI_BASE_URL"
    if ! soul_confirm_default_no "Reconfigure llama.cpp anyway?"; then
      printf 'Leaving existing configuration unchanged.\n'
      exit 0
    fi
  fi
fi

default_server="${SOUL_LLAMA_SERVER:-}"
if [ -z "$default_server" ] && soul_have llama-server; then
  default_server="$(command -v llama-server)"
fi
if [ -z "$default_server" ]; then
  default_server="llama-server"
fi

default_host="${SOUL_LLAMA_HOST:-127.0.0.1}"
default_port="${SOUL_LLAMA_PORT:-8082}"
default_base="${SOUL_OPENAI_BASE_URL:-http://${default_host}:${default_port}/v1}"
default_alias="${SOUL_MODEL_ALIAS:-soul-qwen3-8b-q4}"
default_model_dir="${SOUL_MODEL_DIR:-./models}"
default_model_file="${SOUL_MODEL_FILE:-Qwen3-8B-Q4_K_M.gguf}"
default_model_url="${SOUL_MODEL_URL:-https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true}"

printf 'Soul/ llama.cpp setup\n'
printf '\n'

llama_server="$(soul_prompt_default "llama-server command/path" "$default_server")"
host="$(soul_prompt_default "llama.cpp bind host" "$default_host")"
port="$(soul_prompt_default "llama.cpp port" "$default_port")"
base_url="$(soul_prompt_default "OpenAI-compatible base URL" "$default_base")"
model_alias="$(soul_prompt_default "Model alias exposed to Soul/" "$default_alias")"

detected_model_path=""
if detected_model_path="$(soul_choose_gguf_file "$default_model_file")" && [ -n "$detected_model_path" ]; then
  printf 'Selected local GGUF model: %s\n' "$detected_model_path"
  model_dir="$(dirname "$detected_model_path")"
  model_file="$(basename "$detected_model_path")"
  model_url="${SOUL_MODEL_URL:-local-detected}"
else
  model_dir="$(soul_prompt_default "Model directory" "$default_model_dir")"
  model_file="$(soul_prompt_default "GGUF model filename, case-sensitive" "$default_model_file")"
  model_url="$(soul_prompt_default "Hugging Face GGUF URL" "$default_model_url")"
fi

model_path="${model_dir%/}/${model_file}"

mkdir -p "$model_dir"

if [ -f "$model_path" ]; then
  if soul_validate_gguf "$model_path"; then
    printf 'OK: existing GGUF model: %s\n' "$model_path"
  else
    printf 'BAD: existing model file is not GGUF: %s\n' "$model_path"
    if soul_confirm_default_yes "Remove and re-download it?"; then
      rm -f "$model_path"
    else
      soul_fail "Cannot continue with invalid GGUF file."
    fi
  fi
fi

if [ ! -f "$model_path" ]; then
  if [ "$model_url" = "local-detected" ]; then
    soul_fail "Selected local model path disappeared: $model_path"
  fi
  printf 'Downloading GGUF model to %s\n' "$model_path"
  curl -fL --retry 5 --retry-delay 3 -C - -o "$model_path" "$model_url"
fi

if ! soul_validate_gguf "$model_path"; then
  printf 'Downloaded file is not a GGUF model.\n' >&2
  printf 'First bytes:\n' >&2
  head -c 200 "$model_path" >&2 || true
  printf '\n' >&2
  rm -f "$model_path"
  soul_fail "Model validation failed."
fi

printf 'OK: GGUF model validated: %s\n' "$model_path"

if ! $download_only; then
  if [ "$llama_server" != "llama-server" ] && [ ! -x "$llama_server" ]; then
    soul_warn "llama-server path is not executable: $llama_server"
  elif [ "$llama_server" = "llama-server" ] && ! soul_have llama-server; then
    soul_warn "llama-server is not currently in PATH."
  fi
fi

soul_backup_env_if_exists
soul_write_env_llamacpp "$base_url" "$model_alias" "$model_dir" "$model_file" "$model_url" "$llama_server" "$host" "$port"

printf '\nWrote %s\n' "$SOUL_ENV_FILE"
printf '\nNext steps:\n'
printf '  make start-llamacpp\n'
printf '  make test-runtime\n'
