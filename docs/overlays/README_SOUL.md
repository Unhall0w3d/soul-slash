# Soul/

Soul/ is a local personal assistant substrate wrapped around a small local LLM runtime.

This initial skeleton is intentionally boring:
- local Ruby CLI
- local llama.cpp/OpenAI-compatible endpoint
- human-readable Soul files
- read-only first skill: `system.status`
- task logs
- reflection candidate staging

The current expected model endpoint is:

```text
http://127.0.0.1:8082/v1
```

The current expected model alias is:

```text
soul-qwen3-8b-q4
```

## First commands

From the project root:

```bash
ruby bin/soul doctor
ruby bin/soul skill system.status
ruby bin/soul ask fast "Say exactly: Soul CLI is online."
ruby bin/soul ask think "In one sentence, why should Soul verify actions before reporting success?"
```

## Environment overrides

```bash
export SOUL_OPENAI_BASE_URL="http://127.0.0.1:8082/v1"
export SOUL_MODEL_ALIAS="soul-qwen3-8b-q4"
```

## Current design rule

No write actions beyond logs/reflection candidates until the verification and approval model is implemented.
