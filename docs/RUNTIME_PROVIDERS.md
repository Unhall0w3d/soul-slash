# Runtime Providers

Soul/ is designed to sit above a local model runtime that exposes an OpenAI-compatible API.

The runtime is not the whole assistant. The runtime supplies language. Soul/ supplies orchestration, skills, verification, workflow state, reflection, and human-approved memory.

## Supported providers

Current intended providers:

- llama.cpp server
- Ollama

## Provider boundary

Soul/ can support both providers because both can expose OpenAI-compatible APIs.

However, model acquisition is provider-specific:

- llama.cpp setup can download GGUF files from Hugging Face.
- Ollama setup should use `ollama pull` and Ollama model names.

Do not pretend those are the same workflow. That is how setup scripts turn into haunted campfire stories.

## llama.cpp

llama.cpp is useful when you want direct control over:

- GGUF model files
- runtime port
- GPU layer settings
- context size
- cache type
- reasoning/template flags
- foreground or service-based execution

Default tested endpoint:

```text
http://127.0.0.1:8082/v1
```

Stable local API alias:

```text
soul-local-chat
```

The alias does not identify the loaded model. Runtime profile status separately
reports the actual model, accelerator, service, and selected-at-login profile.

Default tested GGUF model:

```text
Qwen3-8B-Q4_K_M.gguf
```

Default tested Hugging Face URL:

```text
https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true
```

Setup:

```bash
make setup-llamacpp
```

Start server:

```bash
make start-llamacpp
```

## Ollama

Ollama is useful when you want a simpler local model manager.

Default endpoint:

```text
http://127.0.0.1:11434/v1
```

Example model:

```text
qwen3:8b
```

Setup:

```bash
make setup-ollama
```

The setup script checks whether the model exists locally and runs `ollama pull` only if needed.

## Manually selected mixed-runtime profiles

An ignored project-local v3 inventory may expose llama.cpp and Ollama profiles
through the same loopback OpenAI endpoint and stable API alias. Each record
declares its runtime, actual model name, API model, accelerator, user service,
endpoint, and Core role. Copy and adapt:

```text
Soul/config/model_runtime_profiles.example.yaml
```

Then set:

```text
SOUL_MODEL_RUNTIME_PROFILES_FILE=Soul/config/model_runtime_profiles.local.yaml
SOUL_LOCAL_OPENAI_DIALECT=auto
```

`auto` follows only the reviewed selected-profile record. It does not inspect
the network, choose a model, switch a service, or provide automatic failover.
llama.cpp idleness is checked through `/slots`; Ollama service health and model
residency are reported separately through `/api/tags` and `/api/ps`. Soul's
active lease store remains authoritative for in-process work in both cases.

The optional Gemma/Ollama deployment commands create only a static, inactive,
unenabled loopback user unit:

```bash
make model-runtime-gemma-plan OLLAMA_SHA256=... GEMMA_MODEL_DIGEST=...
make model-runtime-gemma-install OLLAMA_SHA256=... GEMMA_MODEL_DIGEST=... \
  CONFIRM=INSTALL_INACTIVE_GEMMA_OLLAMA_UNIT
make model-runtime-gemma-status
```

Installation does not start, enable, select, or make Gemma the default Core.
Runtime changes still use the authenticated dashboard preview/digest gate.

## Environment variables

Soul/ should read local runtime settings from `.env` when present.

Important values:

```text
SOUL_RUNTIME_PROVIDER
SOUL_OPENAI_BASE_URL
SOUL_MODEL_ALIAS
```

Provider-specific values:

```text
SOUL_MODEL_DIR
SOUL_MODEL_FILE
SOUL_MODEL_URL
SOUL_OLLAMA_MODEL
```

See:

```text
.env.example
```

## Detection

Run:

```bash
make detect
```

Detection checks:

- `llama-server`
- `ollama`
- common OpenAI-compatible `/v1` endpoints
- Ollama native `/api/tags`
- current `.env`
- local GGUF files in `./models` and `~/Downloads`

## Validation

A runtime is usable only if Soul/ can:

- reach the base endpoint
- list models or otherwise confirm model availability
- complete a small FAST-mode chat request
- report failures clearly

No green lights without gauges.
