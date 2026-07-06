.RECIPEPREFIX := >
SHELL := /usr/bin/env bash

# Soul/ local model runtime v0.1
# Runtime target:
#   /usr/local/bin/llama-server
#   user systemd service: llama-server.service
#   model: Qwen3 8B Q4_K_M
#   GPU: GTX 1070 via NVIDIA/CUDA llama.cpp

USER_HOME := $(HOME)

PROJECT_ROOT ?= $(USER_HOME)/Projects/soul
MODEL_DIR ?= $(USER_HOME)/ai_models
MODEL_FILE ?= Qwen3-8B-Q4_K_M.gguf
MODEL_PATH ?= $(MODEL_DIR)/$(MODEL_FILE)
MODEL_URL ?= https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true

LLAMA_SERVER ?= /usr/local/bin/llama-server
SERVICE_NAME ?= llama-server.service
SYSTEMD_USER_DIR ?= $(USER_HOME)/.config/systemd/user
SERVICE_FILE ?= $(SYSTEMD_USER_DIR)/$(SERVICE_NAME)
DROPIN_DIR ?= $(SYSTEMD_USER_DIR)/$(SERVICE_NAME).d
OVERRIDE_FILE ?= $(DROPIN_DIR)/override.conf

RUN_DIR ?= $(PROJECT_ROOT)/run
LOG_DIR ?= $(PROJECT_ROOT)/logs

MODEL_ALIAS ?= soul-qwen3-8b-q4
HOST ?= 127.0.0.1
PORT ?= 8082
BASE_URL ?= http://$(HOST):$(PORT)
OPENAI_BASE_URL ?= $(BASE_URL)/v1

# GTX 1070 / Pascal-safe defaults.
CTX_SIZE ?= 4096
N_PREDICT ?= 2048
GPU_LAYERS ?= 999
THREADS ?= 8
PARALLEL ?= 1
BATCH_SIZE ?= 1024
UBATCH_SIZE ?= 256

# Pascal-safe KV cache defaults.
# Quantized V cache requires Flash Attention in current llama.cpp builds,
# and Flash Attention is disabled on this GTX 1070 path.
CACHE_TYPE_K ?= f16
CACHE_TYPE_V ?= f16
FLASH_ATTN ?= off

TEMP ?= 0.6
TOP_K ?= 20
TOP_P ?= 0.95
MIN_P ?= 0.0
PRESENCE_PENALTY ?= 0.5
REPEAT_PENALTY ?= 1.05

# Soul/ request-mode defaults.
FAST_MAX_TOKENS ?= 768
THINK_MAX_TOKENS ?= 2048
FAST_TEMP ?= 0.2
THINK_TEMP ?= 0.4

.PHONY: help check init download-model show-service service-update start stop restart enable disable status health wait test-chat test-fast test-think test-modes logs gpu service-cat service-edit foreground clean-runtime

help:
> @echo "Soul/ llama.cpp runtime Makefile"
> @echo
> @echo "Common targets:"
> @echo "  make check             Validate binary, service, GPU, and model path assumptions"
> @echo "  make download-model    Download Qwen3 8B Q4_K_M to $(MODEL_PATH)"
> @echo "  make service-update    Write user systemd override for Soul/ Qwen3 runtime"
> @echo "  make restart           Restart llama-server user service and run fast smoke test"
> @echo "  make start             Start llama-server user service"
> @echo "  make stop              Stop llama-server user service"
> @echo "  make status            Show systemd status"
> @echo "  make health            Check /health"
> @echo "  make test-fast         Test fast /no_think mode"
> @echo "  make test-think        Test thinking mode"
> @echo "  make test-modes        Test both fast and think modes"
> @echo "  make logs              Follow user journal logs"
> @echo "  make gpu               Show nvidia-smi"
> @echo "  make foreground        Run llama-server directly in foreground for debugging"
> @echo
> @echo "Override examples:"
> @echo "  make service-update CTX_SIZE=6144"
> @echo "  make service-update CTX_SIZE=4096 CACHE_TYPE_K=f16 CACHE_TYPE_V=f16 FLASH_ATTN=off"
> @echo "  make test-think THINK_MAX_TOKENS=3072"
> @echo "  make foreground CTX_SIZE=4096"

check:
> @echo "Checking Soul/ llama.cpp runtime..."
> @command -v curl >/dev/null || { echo "Missing curl"; exit 1; }
> @command -v python >/dev/null || { echo "Missing python"; exit 1; }
> @command -v systemctl >/dev/null || { echo "Missing systemctl"; exit 1; }
> @command -v nvidia-smi >/dev/null || { echo "Missing nvidia-smi"; exit 1; }
> @test -x "$(LLAMA_SERVER)" || { echo "Missing executable llama-server at $(LLAMA_SERVER)"; exit 1; }
> @echo "OK: llama-server: $(LLAMA_SERVER)"
> @"$(LLAMA_SERVER)" --version || true
> @echo
> @echo "Service file:"
> @if [ -f "$(SERVICE_FILE)" ]; then \
>   echo "OK: $(SERVICE_FILE)"; \
> else \
>   echo "WARNING: $(SERVICE_FILE) does not exist yet."; \
>   echo "         make service-update will create a user service."; \
> fi
> @echo
> @echo "Model path:"
> @if [ -f "$(MODEL_PATH)" ]; then \
>   if [ "$$(head -c 4 "$(MODEL_PATH)")" = "GGUF" ]; then \
>     echo "OK: $(MODEL_PATH)"; \
>     du -h "$(MODEL_PATH)"; \
>   else \
>     echo "BAD: $(MODEL_PATH) exists but is not a GGUF file."; \
>     echo "First bytes:"; \
>     head -c 120 "$(MODEL_PATH)" || true; \
>     echo; \
>   fi; \
> else \
>   echo "Missing model: $(MODEL_PATH)"; \
>   echo "Run: make download-model"; \
> fi
> @echo
> @echo "NVIDIA GPU:"
> @nvidia-smi --query-gpu=name,memory.total,memory.used,power.draw --format=csv,noheader

init:
> @mkdir -p "$(PROJECT_ROOT)" "$(MODEL_DIR)" "$(RUN_DIR)" "$(LOG_DIR)" "$(SYSTEMD_USER_DIR)" "$(DROPIN_DIR)"

download-model: init
> @if [ -f "$(MODEL_PATH)" ]; then \
>   if [ "$$(head -c 4 "$(MODEL_PATH)")" = "GGUF" ]; then \
>     echo "Model already exists and looks valid: $(MODEL_PATH)"; \
>     du -h "$(MODEL_PATH)"; \
>     exit 0; \
>   else \
>     echo "Existing model file is not GGUF. Removing bad file: $(MODEL_PATH)"; \
>     head -c 120 "$(MODEL_PATH)" || true; \
>     echo; \
>     rm -f "$(MODEL_PATH)"; \
>   fi; \
> fi
> @echo "Downloading Qwen3 8B Q4_K_M GGUF to $(MODEL_PATH)..."
> @curl -fL --retry 5 --retry-delay 3 -C - -o "$(MODEL_PATH)" "$(MODEL_URL)"
> @if [ "$$(head -c 4 "$(MODEL_PATH)")" != "GGUF" ]; then \
>   echo "Downloaded file is not a GGUF model. First bytes:"; \
>   head -c 200 "$(MODEL_PATH)" || true; \
>   echo; \
>   rm -f "$(MODEL_PATH)"; \
>   exit 1; \
> fi
> @du -h "$(MODEL_PATH)"

service-update: init
> @test -x "$(LLAMA_SERVER)" || { echo "Missing executable llama-server at $(LLAMA_SERVER)"; exit 1; }
> @test -f "$(MODEL_PATH)" || { echo "Missing model at $(MODEL_PATH). Run: make download-model"; exit 1; }
> @if [ "$$(head -c 4 "$(MODEL_PATH)")" != "GGUF" ]; then \
>   echo "Model file is not valid GGUF: $(MODEL_PATH)"; \
>   head -c 120 "$(MODEL_PATH)" || true; \
>   echo; \
>   exit 1; \
> fi
> @if [ ! -f "$(SERVICE_FILE)" ]; then \
>   echo "Creating base user service: $(SERVICE_FILE)"; \
>   printf '%s\n' \
>     '[Unit]' \
>     'Description=llama.cpp Local AI Server' \
>     'After=network-online.target' \
>     '' \
>     '[Service]' \
>     'Type=simple' \
>     'ExecStart=/usr/local/bin/llama-server --version' \
>     'Restart=on-failure' \
>     'RestartSec=3' \
>     '' \
>     '[Install]' \
>     'WantedBy=default.target' \
>     > "$(SERVICE_FILE)"; \
> fi
> @echo "Writing override: $(OVERRIDE_FILE)"
> @printf '%s\n' \
>   '[Service]' \
>   'ExecStart=' \
>   'ExecStart=$(LLAMA_SERVER) --model $(MODEL_PATH) --alias $(MODEL_ALIAS) --host $(HOST) --port $(PORT) --jinja --reasoning-format deepseek --n-gpu-layers $(GPU_LAYERS) --split-mode none --main-gpu 0 --ctx-size $(CTX_SIZE) --predict $(N_PREDICT) --threads $(THREADS) --parallel $(PARALLEL) --batch-size $(BATCH_SIZE) --ubatch-size $(UBATCH_SIZE) --cache-type-k $(CACHE_TYPE_K) --cache-type-v $(CACHE_TYPE_V) --flash-attn $(FLASH_ATTN) --temp $(TEMP) --top-k $(TOP_K) --top-p $(TOP_P) --min-p $(MIN_P) --presence-penalty $(PRESENCE_PENALTY) --repeat-penalty $(REPEAT_PENALTY) --no-context-shift' \
>   'Environment=CUDA_VISIBLE_DEVICES=0' \
>   'Restart=on-failure' \
>   'RestartSec=3' \
>   > "$(OVERRIDE_FILE)"
> @systemctl --user daemon-reload
> @echo "Updated $(SERVICE_NAME). Run: make restart"

start:
> @systemctl --user start "$(SERVICE_NAME)"

stop:
> @systemctl --user stop "$(SERVICE_NAME)" || true

restart:
> @systemctl --user restart "$(SERVICE_NAME)"
> @$(MAKE) wait
> @$(MAKE) test-fast

enable:
> @systemctl --user enable "$(SERVICE_NAME)"

disable:
> @systemctl --user disable "$(SERVICE_NAME)"

status:
> @systemctl --user status "$(SERVICE_NAME)" --no-pager || true

service-cat:
> @systemctl --user cat "$(SERVICE_NAME)" || true

service-edit:
> @systemctl --user edit "$(SERVICE_NAME)"

health:
> @curl -fsS "$(BASE_URL)/health" || true
> @echo

wait:
> @echo "Waiting for llama-server health at $(BASE_URL)/health ..."
> @for i in $$(seq 1 120); do \
>   if curl -fsS "$(BASE_URL)/health" 2>/dev/null | grep -q '"ok"'; then \
>     echo "llama-server is healthy."; \
>     exit 0; \
>   fi; \
>   sleep 2; \
> done; \
> echo "Timed out waiting for llama-server."; \
> echo "Recent logs:"; \
> journalctl --user -u "$(SERVICE_NAME)" -n 120 --no-pager || true; \
> exit 1

test-chat: test-fast

test-fast:
> @echo "Testing FAST mode at $(OPENAI_BASE_URL) ..."
> @curl -sS "$(OPENAI_BASE_URL)/chat/completions" \
>   -H "Content-Type: application/json" \
>   -d '{"model":"$(MODEL_ALIAS)","messages":[{"role":"system","content":"You are the local Soul/ runtime. Answer plainly and briefly. Do not explain your reasoning."},{"role":"user","content":"/no_think\nSay exactly: Soul FAST mode is online."}],"max_tokens":$(FAST_MAX_TOKENS),"temperature":$(FAST_TEMP)}' \
>   | python -c 'import sys,json; data=json.load(sys.stdin); msg=data.get("choices",[{}])[0].get("message",{}); usage=data.get("usage",{}); content=(msg.get("content") or "").strip(); reasoning=(msg.get("reasoning_content") or "").strip(); print(content if content else "[no final content]"); print("completion_tokens=%s total_tokens=%s" % (usage.get("completion_tokens"), usage.get("total_tokens")))'

test-think:
> @echo "Testing THINK mode at $(OPENAI_BASE_URL) ..."
> @curl -sS "$(OPENAI_BASE_URL)/chat/completions" \
>   -H "Content-Type: application/json" \
>   -d '{"model":"$(MODEL_ALIAS)","messages":[{"role":"system","content":"You are the local Soul/ runtime. You may reason internally, but your final answer must be concise."},{"role":"user","content":"Think through this briefly, then answer in one sentence: why should Soul/ do a dry run before moving files to Trash?"}],"max_tokens":$(THINK_MAX_TOKENS),"temperature":$(THINK_TEMP)}' \
>   | python -c 'import sys,json; data=json.load(sys.stdin); msg=data.get("choices",[{}])[0].get("message",{}); usage=data.get("usage",{}); content=(msg.get("content") or "").strip(); reasoning=(msg.get("reasoning_content") or "").strip(); print(content if content else "[no final content; reasoning preview follows]\n" + reasoning[-1200:]); print("completion_tokens=%s total_tokens=%s" % (usage.get("completion_tokens"), usage.get("total_tokens")))'

test-modes: test-fast test-think

logs:
> @journalctl --user -u "$(SERVICE_NAME)" -f

gpu:
> @nvidia-smi

foreground:
> @test -x "$(LLAMA_SERVER)" || { echo "Missing executable llama-server at $(LLAMA_SERVER)"; exit 1; }
> @test -f "$(MODEL_PATH)" || { echo "Missing model at $(MODEL_PATH). Run: make download-model"; exit 1; }
> @CUDA_VISIBLE_DEVICES=0 "$(LLAMA_SERVER)" \
>   --model "$(MODEL_PATH)" \
>   --alias "$(MODEL_ALIAS)" \
>   --host "$(HOST)" \
>   --port "$(PORT)" \
>   --jinja \
>   --reasoning-format deepseek \
>   --n-gpu-layers "$(GPU_LAYERS)" \
>   --split-mode none \
>   --main-gpu 0 \
>   --ctx-size "$(CTX_SIZE)" \
>   --predict "$(N_PREDICT)" \
>   --threads "$(THREADS)" \
>   --parallel "$(PARALLEL)" \
>   --batch-size "$(BATCH_SIZE)" \
>   --ubatch-size "$(UBATCH_SIZE)" \
>   --cache-type-k "$(CACHE_TYPE_K)" \
>   --cache-type-v "$(CACHE_TYPE_V)" \
>   --flash-attn "$(FLASH_ATTN)" \
>   --temp "$(TEMP)" \
>   --top-k "$(TOP_K)" \
>   --top-p "$(TOP_P)" \
>   --min-p "$(MIN_P)" \
>   --presence-penalty "$(PRESENCE_PENALTY)" \
>   --repeat-penalty "$(REPEAT_PENALTY)" \
>   --no-context-shift

clean-runtime:
> @rm -rf "$(RUN_DIR)"
> @echo "Removed runtime directory: $(RUN_DIR)"
