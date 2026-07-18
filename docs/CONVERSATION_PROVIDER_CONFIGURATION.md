# Conversation Provider Configuration

Phase 2 provides three provider shapes.

## Local OpenAI-compatible

Provider ID:

```text
local.openai_compatible
```

Environment:

```text
SOUL_LOCAL_OPENAI_BASE_URL
SOUL_LOCAL_OPENAI_MODEL
SOUL_LOCAL_OPENAI_DIALECT
```

Fallback endpoint:

```text
http://127.0.0.1:8080/v1
```

`OPENAI_BASE_URL` and `SOUL_LOCAL_MODEL` are accepted as compatibility fallbacks.

This shape is suitable for llama.cpp server and other local OpenAI-compatible runtimes.

With a v3 multi-runtime profile inventory, set:

```text
SOUL_LOCAL_OPENAI_DIALECT=auto
```

Soul follows the manually selected profile and uses the matching llama.cpp or
Ollama request shape. For a fixed Ollama OpenAI-compatible endpoint, set:

```text
SOUL_LOCAL_OPENAI_DIALECT=ollama
```

Soul then requests Ollama's explicit `none` reasoning mode. This prevents
hidden reasoning from consuming the bounded response budget before a visible
answer or structured artifact is emitted. Leave the value blank for llama.cpp
and other OpenAI-compatible runtimes.

## Local Ollama

Provider ID:

```text
local.ollama
```

Environment:

```text
OLLAMA_HOST
SOUL_OLLAMA_MODEL
```

Fallback endpoint:

```text
http://127.0.0.1:11434
```

`OLLAMA_MODEL` is accepted as a model-name fallback.

## Cloud OpenAI-compatible

Provider ID:

```text
cloud.openai_compatible
```

Environment:

```text
SOUL_CLOUD_OPENAI_BASE_URL
SOUL_CLOUD_OPENAI_MODEL
SOUL_CLOUD_OPENAI_CREDENTIAL_ENV
```

Default credential variable name:

```text
SOUL_CLOUD_OPENAI_API_KEY
```

The cloud shape is disabled unless endpoint, model, and credential are present.

Phase 2 does not route conversation to the cloud provider.

## Health checks

OpenAI-compatible providers are probed using:

```text
GET /v1/models
```

Ollama providers are probed using:

```text
GET /api/tags
```

Probe results normalize:

```text
available
unhealthy
misconfigured
timeout
unavailable
```

Health checks use bounded connection, read, and write timeouts.

## Privacy behavior

The provider definition records whether use is:

```text
local_only
local_network
cloud
```

Later orchestration phases must compare request privacy requirements with provider privacy classes before routing a conversation turn.
