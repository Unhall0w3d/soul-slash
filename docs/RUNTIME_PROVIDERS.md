# Runtime Providers

Soul/ is designed to sit above a local model runtime that exposes an OpenAI-compatible API.

The runtime is not the whole assistant. The runtime supplies language. Soul/ supplies orchestration, skills, verification, workflow state, reflection, and human-approved memory.

## Supported providers

Current intended providers:

- llama.cpp server
- Ollama

## Provider: llama.cpp

llama.cpp is the original tested runtime for Soul/.

### Default endpoint

```text
http://127.0.0.1:8082/v1
```

### Default model alias

```text
soul-qwen3-8b-q4
```

### Default GGUF model

```text
Qwen3-8B-Q4_K_M.gguf
```

### Default Hugging Face URL

```text
https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true
```

### Why llama.cpp is useful for Soul/

llama.cpp gives direct control over:

- GGUF file selection
- runtime port
- GPU layer settings
- context size
- cache type
- reasoning/template flags
- foreground or service-based execution

### llama.cpp setup shape

Future setup automation should:

1. detect `llama-server`
2. ask for a Hugging Face GGUF URL or use the tested default
3. ask for the exact model filename when needed
4. download into `./models`
5. validate GGUF magic bytes
6. start or validate a local server
7. write `.env`

## Provider: Ollama

Ollama is supported through its OpenAI-compatible endpoint.

### Default endpoint

```text
http://127.0.0.1:11434/v1
```

### Example model

```text
qwen3:8b
```

### Why Ollama is useful for Soul/

Ollama gives a simpler runtime experience for users who do not want to manage GGUF files and llama.cpp server flags directly.

### Ollama setup shape

Future setup automation should:

1. detect `ollama`
2. check whether the Ollama service is reachable
3. ask for an Ollama model name or use a safe default
4. run `ollama pull <model>`
5. validate `/v1/models`
6. write `.env`

## Honest boundary

Soul/ can support both providers because both can expose OpenAI-compatible APIs.

However, model acquisition is provider-specific:

- llama.cpp setup can download GGUF files from Hugging Face.
- Ollama setup should use `ollama pull` and Ollama model names.

Treating these as the same thing is how setup scripts become folklore with exit codes.

## Environment variables

Soul/ should read local runtime settings from `.env` when present.

See:

```text
.env.example
```

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

## Detection policy

Future detection should follow this order:

1. If `.env` exists, prefer it.
2. If no `.env`, detect installed providers:
   - `llama-server`
   - `ollama`
3. Probe common endpoints:
   - `http://127.0.0.1:8082/v1`
   - `http://127.0.0.1:8080/v1`
   - `http://127.0.0.1:11434/v1`
4. If both providers are available, ask the user which one to use.
5. If neither provider is available, print requirements and exit cleanly.

## Validation policy

A runtime is usable only if Soul/ can:

- reach the base endpoint
- list models or otherwise confirm model availability
- complete a small FAST-mode chat request
- report failures clearly

No green lights without gauges.
