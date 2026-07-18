#!/usr/bin/env bash
set -euo pipefail

SOUL_PROJECT_ROOT="${SOUL_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SOUL_ENV_FILE="${SOUL_ENV_FILE:-${SOUL_PROJECT_ROOT}/.env}"

soul_log() {
  printf '%s\n' "$*"
}

soul_warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

soul_fail() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

soul_have() {
  command -v "$1" >/dev/null 2>&1
}

soul_pick_python() {
  if soul_have python3; then
    printf 'python3\n'
  elif soul_have python; then
    printf 'python\n'
  else
    printf '\n'
  fi
}

soul_load_env() {
  if [ -f "$SOUL_ENV_FILE" ]; then
    local line key value first last
    while IFS= read -r line || [ -n "$line" ]; do
      line="${line%$'\r'}"
      [[ "$line" =~ ^[[:space:]]*$ || "$line" =~ ^[[:space:]]*# ]] && continue
      key="${line%%=*}"
      value="${line#*=}"
      [[ "$line" == *=* ]] || soul_fail "Invalid .env line without '=' in ${SOUL_ENV_FILE}."
      [[ "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || soul_fail "Invalid .env key in ${SOUL_ENV_FILE}."
      if [ "${#value}" -ge 2 ]; then
        first="${value:0:1}"
        last="${value: -1}"
        if { [ "$first" = '"' ] && [ "$last" = '"' ]; } || { [ "$first" = "'" ] && [ "$last" = "'" ]; }; then
          value="${value:1:${#value}-2}"
        fi
      fi
      printf -v "$key" '%s' "$value"
      export "$key"
    done < "$SOUL_ENV_FILE"
  fi
}

soul_prompt_default() {
  local prompt="$1"
  local default="$2"
  local value=""
  printf '%s [%s]: ' "$prompt" "$default" >&2
  read -r value || true
  if [ -z "$value" ]; then
    printf '%s\n' "$default"
  else
    printf '%s\n' "$value"
  fi
}

soul_confirm_default_yes() {
  local prompt="$1"
  local answer=""
  printf '%s [Y/n]: ' "$prompt" >&2
  read -r answer || true
  case "${answer,,}" in
    n|no) return 1 ;;
    *) return 0 ;;
  esac
}

soul_confirm_default_no() {
  local prompt="$1"
  local answer=""
  printf '%s [y/N]: ' "$prompt" >&2
  read -r answer || true
  case "${answer,,}" in
    y|yes) return 0 ;;
    *) return 1 ;;
  esac
}

soul_backup_env_if_exists() {
  if [ -f "$SOUL_ENV_FILE" ]; then
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    cp "$SOUL_ENV_FILE" "${SOUL_ENV_FILE}.backup-${ts}"
    soul_log "Backed up existing .env to ${SOUL_ENV_FILE}.backup-${ts}"
  fi
}

soul_validate_gguf() {
  local file="$1"
  [ -f "$file" ] || return 1
  [ "$(head -c 4 "$file" 2>/dev/null || true)" = "GGUF" ]
}

soul_http_ok() {
  local url="$1"
  curl -fsS --max-time 3 "$url" >/dev/null 2>&1
}

soul_endpoint_models_ok() {
  local base_url="$1"
  soul_http_ok "${base_url%/}/models"
}

soul_ollama_native_ok() {
  local root_url="${1:-http://127.0.0.1:11434}"
  soul_http_ok "${root_url%/}/api/tags"
}

soul_endpoint_chat_ok() {
  local base_url="$1"
  soul_http_ok "${base_url%/}/chat/completions"
}

soul_find_gguf_files() {
  local search_roots=()
  search_roots+=("${SOUL_PROJECT_ROOT}/models")
  if [ -n "${HOME:-}" ]; then
    search_roots+=("${HOME}/Downloads")
  fi

  local root
  for root in "${search_roots[@]}"; do
    [ -d "$root" ] || continue
    find "$root" -maxdepth 2 -type f -iname '*.gguf' -print 2>/dev/null | sort
  done
}

soul_choose_gguf_file() {
  local default_file="$1"
  mapfile -t gguf_files < <(soul_find_gguf_files)

  if [ "${#gguf_files[@]}" -eq 0 ]; then
    printf '\n'
    return 1
  fi

  printf 'Detected local GGUF model files:\n' >&2
  local i=1
  local file
  for file in "${gguf_files[@]}"; do
    if [ "$i" -gt 20 ]; then
      printf '  ... showing first 20 only\n' >&2
      break
    fi
    if soul_validate_gguf "$file"; then
      printf '  %2d) %s\n' "$i" "$file" >&2
    else
      printf '  %2d) %s [not validated]\n' "$i" "$file" >&2
    fi
    i=$((i + 1))
  done

  printf '  M) manually enter path or download URL flow\n' >&2
  printf '\n' >&2

  local default_choice=""
  local idx=1
  for file in "${gguf_files[@]}"; do
    if [ "$(basename "$file")" = "$default_file" ] && soul_validate_gguf "$file"; then
      default_choice="$idx"
      break
    fi
    idx=$((idx + 1))
  done
  if [ -z "$default_choice" ]; then
    default_choice="1"
  fi

  local choice
  choice="$(soul_prompt_default "Use detected GGUF model" "$default_choice")"

  case "${choice,,}" in
    m|manual)
      printf '\n'
      return 1
      ;;
    '' )
      choice="$default_choice"
      ;;
  esac

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#gguf_files[@]}" ]; then
    file="${gguf_files[$((choice - 1))]}"
    if soul_validate_gguf "$file"; then
      printf '%s\n' "$file"
      return 0
    fi
    soul_warn "Selected file is not a valid GGUF: $file"
    return 1
  fi

  soul_warn "Invalid model selection: $choice"
  printf '\n'
  return 1
}

soul_write_env_llamacpp() {
  local base_url="$1"
  local alias="$2"
  local model_dir="$3"
  local model_file="$4"
  local model_url="$5"
  local llama_server="$6"
  local host="$7"
  local port="$8"

  cat > "$SOUL_ENV_FILE" <<EOF
# Soul/ local runtime configuration.
# Generated by scripts/soul-setup-llamacpp.sh

SOUL_RUNTIME_PROVIDER=llamacpp
SOUL_OPENAI_BASE_URL=${base_url}
SOUL_MODEL_ALIAS=${alias}

SOUL_MODEL_DIR=${model_dir}
SOUL_MODEL_FILE=${model_file}
SOUL_MODEL_URL=${model_url}
SOUL_LLAMA_SERVER=${llama_server}

SOUL_LLAMA_HOST=${host}
SOUL_LLAMA_PORT=${port}
SOUL_CTX_SIZE=${SOUL_CTX_SIZE:-4096}
SOUL_N_PREDICT=${SOUL_N_PREDICT:-2048}
SOUL_GPU_LAYERS=${SOUL_GPU_LAYERS:-999}
SOUL_CACHE_TYPE_K=${SOUL_CACHE_TYPE_K:-f16}
SOUL_CACHE_TYPE_V=${SOUL_CACHE_TYPE_V:-f16}
SOUL_FLASH_ATTN=${SOUL_FLASH_ATTN:-off}
SOUL_REASONING_FORMAT=${SOUL_REASONING_FORMAT:-deepseek}
SOUL_USE_JINJA=${SOUL_USE_JINJA:-true}

SOUL_FAST_MAX_TOKENS=${SOUL_FAST_MAX_TOKENS:-768}
SOUL_THINK_MAX_TOKENS=${SOUL_THINK_MAX_TOKENS:-2048}
SOUL_FAST_TEMP=${SOUL_FAST_TEMP:-0.2}
SOUL_THINK_TEMP=${SOUL_THINK_TEMP:-0.4}
EOF
}

soul_write_env_ollama() {
  local base_url="$1"
  local model="$2"

  cat > "$SOUL_ENV_FILE" <<EOF
# Soul/ local runtime configuration.
# Generated by scripts/soul-setup-ollama.sh

SOUL_RUNTIME_PROVIDER=ollama
SOUL_OPENAI_BASE_URL=${base_url}
SOUL_MODEL_ALIAS=${model}
SOUL_OLLAMA_MODEL=${model}

SOUL_FAST_MAX_TOKENS=${SOUL_FAST_MAX_TOKENS:-768}
SOUL_THINK_MAX_TOKENS=${SOUL_THINK_MAX_TOKENS:-2048}
SOUL_FAST_TEMP=${SOUL_FAST_TEMP:-0.2}
SOUL_THINK_TEMP=${SOUL_THINK_TEMP:-0.4}
EOF
}
