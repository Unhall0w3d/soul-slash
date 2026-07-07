# Soul/ Runtime Provider Docs Overlay

This overlay is step 1 of the public setup cleanup.

It adds documentation and configuration templates for supporting both llama.cpp server and Ollama.

It does not replace the Makefile yet. That comes in the next overlay.

## What this overlay adds

```text
.env.example
docs/GETTING_STARTED.md
docs/RUNTIME_PROVIDERS.md
docs/REQUIREMENTS.md
docs/overlays/README_RUNTIME_PROVIDER_DOCS_OVERLAY.md
```

## Intent

This overlay defines the public setup contract before changing automation.

Soul/ should be able to run against any local runtime that exposes an OpenAI-compatible API for chat completions and model listing.

Current supported providers:

- `llamacpp`
- `ollama`

## Important distinction

llama.cpp and Ollama are both supported at the API layer, but model setup is different.

### llama.cpp

Soul/ can support direct GGUF download from Hugging Face for llama.cpp.

Default tested model:

```text
Qwen3-8B-Q4_K_M.gguf
```

Default tested model URL:

```text
https://huggingface.co/Qwen/Qwen3-8B-GGUF/resolve/main/Qwen3-8B-Q4_K_M.gguf?download=true
```

Default tested endpoint:

```text
http://127.0.0.1:8082/v1
```

### Ollama

Soul/ can support Ollama through its OpenAI-compatible API endpoint.

Default endpoint:

```text
http://127.0.0.1:11434/v1
```

Ollama model acquisition should use Ollama model names and `ollama pull`, not arbitrary Hugging Face GGUF URLs unless the user intentionally builds/imports a model through Ollama.

## Install

From the repo root:

```bash
unzip ~/Downloads/soul_runtime_provider_docs_overlay.zip
```

## Suggested commit

```bash
git add .
git commit -m "Document runtime provider setup contract"
git push origin main
```
