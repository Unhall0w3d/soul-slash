# Model Runtime Assessment Phase 12

Phase 12 adds read-only local model runtime assessment.

Commands:

```bash
ruby bin/soul assess models
ruby bin/soul assess models --json
ruby bin/soul assess models --processes
ruby bin/soul assess models --processes --json
```

Alias:

```bash
ruby bin/soul assess model-runtime
```

## What it detects

```text
llama.cpp / OpenAI-compatible endpoint
Ollama endpoint
llama / ollama command availability
NVIDIA telemetry availability
ROCm telemetry availability
Vulkan info availability
PCI display devices when lspci exists
local model-file paths
capability gaps
```

## Default endpoints

```text
llama.cpp/OpenAI-compatible: http://127.0.0.1:8082
Ollama: http://127.0.0.1:11434
```

Environment overrides:

```text
SOUL_LOCAL_LLM_URL
SOUL_LLAMA_CPP_URL
OLLAMA_HOST
```

## Boundaries

This phase is read-only.

Soul must not:

```text
download models
modify model files
start or stop model services
change GPU settings
print API keys
scan unrelated user data
```

## Future phases

Future phases should add:

```text
curated model capability registry
vision model suitability assessment
task-to-model routing policy
local screenshot ingestion capability assessment
speech-to-text / text-to-speech assessment
model upgrade proposal generation
```
