# Requirements

Soul/ is early experimental local assistant software.

The project is currently Linux-first because the active filesystem workflows use Linux-style Trash behavior. The CLI and provider model are intended to become more portable over time, but the safest current assumption is Linux.

## Required

- Ruby
- Git
- Make
- curl
- unzip
- A local OpenAI-compatible model runtime

Supported runtime providers:

- llama.cpp server
- Ollama

## Recommended

- jq
- zip
- Python 3, useful for helper scripts and local packaging workflows
- A GPU-supported local model runtime where available

## Optional

- systemd user services for managing llama.cpp server on Linux
- NVIDIA, AMD, Metal, or CPU runtime acceleration depending on platform and provider
- GitHub CLI for repository publishing and PR workflows

## Runtime provider support

Soul/ talks to model runtimes through an OpenAI-compatible API shape.

That means the project can support both llama.cpp server and Ollama at the API layer.

The setup workflows differ:

| Provider | API support | Model setup |
|---|---|---|
| llama.cpp | OpenAI-compatible local server | GGUF file, often downloaded from Hugging Face |
| Ollama | OpenAI-compatible local endpoint | Ollama model name, usually installed with `ollama pull` |

## Current tested llama.cpp defaults

```text
Endpoint: http://127.0.0.1:8082/v1
Model alias: soul-qwen3-8b-q4
Model file: Qwen3-8B-Q4_K_M.gguf
Model source: Qwen/Qwen3-8B-GGUF on Hugging Face
Context size: 4096
Prediction budget: 2048
K/V cache: f16/f16
Flash attention: off
Reasoning format: deepseek
Jinja templates: enabled
```

These are tested defaults, not universal requirements.

## Current Ollama defaults

```text
Endpoint: http://127.0.0.1:11434/v1
Example model: qwen3:8b
```

Ollama support should use Ollama model names and `ollama pull`.

Do not assume an arbitrary Hugging Face GGUF URL can be used directly with Ollama without an intentional import/build step.
