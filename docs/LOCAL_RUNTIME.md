# Local Runtime

Current development assumes a local llama.cpp server exposing an OpenAI-compatible API.

## Endpoint

```text
http://127.0.0.1:8082/v1
```

## Model alias

```text
soul-local-chat
```

This is a neutral OpenAI-compatible API alias. Inspect the Model runtime card
for the actual model name, accelerator, service, and selected-at-login profile.

## Modes

### FAST mode

Used for routine interaction and intent classification.

```text
/no_think
max_tokens: 768
temperature: 0.2
```

### THINK mode

Used for planning and reflection.

```text
max_tokens: 2048
temperature: 0.4
```

## Health checks

```bash
ruby bin/soul doctor
ruby bin/soul skill system.status
```

## Runtime notes

Qwen3 thinking mode can consume response budget before producing final content. FAST mode uses `/no_think` to avoid that behavior for routine tasks.
