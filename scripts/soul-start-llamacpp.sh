#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/soul-common.sh
. "${SCRIPT_DIR}/soul-common.sh"

soul_load_env

provider="${SOUL_RUNTIME_PROVIDER:-}"
[ "$provider" = "llamacpp" ] || soul_fail "SOUL_RUNTIME_PROVIDER must be llamacpp for this target."

llama_server="${SOUL_LLAMA_SERVER:-llama-server}"
model_dir="${SOUL_MODEL_DIR:-./models}"
model_file="${SOUL_MODEL_FILE:-}"
model_alias="${SOUL_MODEL_ALIAS:-soul-local-chat}"
host="${SOUL_LLAMA_HOST:-127.0.0.1}"
port="${SOUL_LLAMA_PORT:-8082}"
model_path="${model_dir%/}/${model_file}"

[ -n "$model_file" ] || soul_fail "SOUL_MODEL_FILE is not set."
[ -f "$model_path" ] || soul_fail "Missing model: $model_path"
soul_validate_gguf "$model_path" || soul_fail "Model is not a valid GGUF file: $model_path"

if [ "$llama_server" = "llama-server" ]; then
  soul_have llama-server || soul_fail "llama-server not found in PATH."
else
  [ -x "$llama_server" ] || soul_fail "llama-server path is not executable: $llama_server"
fi

args=(
  --model "$model_path"
  --alias "$model_alias"
  --host "$host"
  --port "$port"
  --ctx-size "${SOUL_CTX_SIZE:-4096}"
  --predict "${SOUL_N_PREDICT:-2048}"
  --n-gpu-layers "${SOUL_GPU_LAYERS:-999}"
  --cache-type-k "${SOUL_CACHE_TYPE_K:-f16}"
  --cache-type-v "${SOUL_CACHE_TYPE_V:-f16}"
  --flash-attn "${SOUL_FLASH_ATTN:-off}"
)

if [ "${SOUL_USE_JINJA:-true}" = "true" ]; then
  args+=(--jinja)
fi

if [ -n "${SOUL_REASONING_FORMAT:-}" ]; then
  args+=(--reasoning-format "${SOUL_REASONING_FORMAT}")
fi

printf 'Starting llama.cpp server...\n'
printf '  server: %s\n' "$llama_server"
printf '  model:  %s\n' "$model_path"
printf '  alias:  %s\n' "$model_alias"
printf '  URL:    http://%s:%s/v1\n' "$host" "$port"
printf '\n'

exec "$llama_server" "${args[@]}"
