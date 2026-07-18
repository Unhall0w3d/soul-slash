#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/soul-common.sh
. "${SCRIPT_DIR}/soul-common.sh"

mode="${1:-all}"
temporary_directory="$(mktemp -d "${TMPDIR:-/tmp}/soul-runtime-test.XXXXXX")"
chmod 700 "$temporary_directory"
trap 'rm -rf -- "$temporary_directory"' EXIT INT TERM

soul_load_env

base_url="${SOUL_OPENAI_BASE_URL:-}"
model="${SOUL_MODEL_ALIAS:-}"
runtime_identity="$(SOUL_PROJECT_ROOT="$SOUL_PROJECT_ROOT" ruby -I"${SOUL_PROJECT_ROOT}/lib" -rsoul_core/model_runtime_profile_registry -e '
  registry = SoulCore::ModelRuntimeProfileRegistry.new(root: ENV.fetch("SOUL_PROJECT_ROOT"), env: ENV)
  profile = registry.selected_profile
  puts [profile.fetch("runtime"), profile.fetch("model_name")].join("|")
' 2>/dev/null || true)"
runtime_provider="${runtime_identity%%|*}"
runtime_model="${runtime_identity#*|}"
[ "$runtime_identity" != "$runtime_model" ] || { runtime_provider="${SOUL_RUNTIME_PROVIDER:-unknown}"; runtime_model="$model"; }

[ -n "$base_url" ] || soul_fail "SOUL_OPENAI_BASE_URL is not set. Run make setup first or create .env."
[ -n "$model" ] || soul_fail "SOUL_MODEL_ALIAS is not set. Run make setup first or create .env."

printf 'Soul/ runtime test\n'
printf 'Provider: %s\n' "$runtime_provider"
printf 'Base URL: %s\n' "$base_url"
printf 'Model:    %s (API alias: %s)\n' "$runtime_model" "$model"
printf '\n'

printf 'Checking model listing...\n'
if curl -fsS "${base_url%/}/models" >"${temporary_directory}/models.json"; then
  printf 'OK: %s/models\n' "${base_url%/}"
else
  soul_fail "Could not reach ${base_url%/}/models"
fi

make_payload() {
  local test_mode="$1"
  ruby -rjson -e '
    mode = ARGV[0]
    model = ENV.fetch("SOUL_MODEL_ALIAS")
    fast = mode == "fast"
    messages = if fast
      [
        {role: "system", content: "You are the local Soul/ runtime. Answer plainly and briefly. Do not explain your reasoning."},
        {role: "user", content: "/no_think\nSay exactly: Soul FAST mode is online."}
      ]
    else
      [
        {role: "system", content: "You are the local Soul/ runtime. You may reason internally, but final output must be concise."},
        {role: "user", content: "In one sentence, explain why Soul/ should do a dry run before moving files to Trash."}
      ]
    end
    payload = {
      model: model,
      messages: messages,
      max_tokens: (fast ? ENV.fetch("SOUL_FAST_MAX_TOKENS", "768").to_i : ENV.fetch("SOUL_THINK_MAX_TOKENS", "2048").to_i),
      temperature: (fast ? ENV.fetch("SOUL_FAST_TEMP", "0.2").to_f : ENV.fetch("SOUL_THINK_TEMP", "0.4").to_f)
    }
    puts JSON.generate(payload)
  ' "$test_mode"
}

run_chat_test() {
  local test_mode="$1"
  local payload_file="${temporary_directory}/chat-${test_mode}.json"
  local response_file="${temporary_directory}/chat-${test_mode}-response.json"

  printf '\nTesting %s mode...\n' "$test_mode"
  make_payload "$test_mode" > "$payload_file"

  curl -fsS "${base_url%/}/chat/completions" \
    -H "Content-Type: application/json" \
    -d @"$payload_file" \
    > "$response_file"

  ruby -rjson -e '
    data = JSON.parse(File.read(ARGV[0]))
    choice = data.fetch("choices", [{}])[0]
    msg = choice.fetch("message", {})
    content = (msg["content"] || "").strip
    reasoning = (msg["reasoning_content"] || "").strip
    usage = data["usage"] || {}
    if content.empty? && !reasoning.empty?
      puts "[no final content; reasoning preview]"
      puts reasoning[-1200, 1200]
    elsif content.empty?
      puts "[no content returned]"
      exit 2
    else
      puts content
    end
    puts "completion_tokens=#{usage["completion_tokens"] || "unknown"} total_tokens=#{usage["total_tokens"] || "unknown"}"
  ' "$response_file"
}

case "$mode" in
  --fast)
    run_chat_test fast
    ;;
  --think)
    run_chat_test think
    ;;
  all|"")
    run_chat_test fast
    run_chat_test think
    ;;
  *)
    soul_fail "Unknown test mode: $mode"
    ;;
esac

printf '\nRuntime test complete.\n'
