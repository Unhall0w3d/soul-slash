# Conversation Provider Contract

Conversational Soul uses a provider-neutral contract so the conversation runtime is not welded to one model server.

Phase 2 defines the contract and health-check foundation. It does not yet replace the deterministic chat responder.

## Provider definition

Every provider declares:

```text
id
label
transport
endpoint
model
privacy_class
capabilities
configured
credential_env
metadata
```

Supported transports:

```text
openai_compatible
ollama
```

Supported privacy classes:

```text
local_only
local_network
cloud
```

Supported capabilities:

```text
chat
streaming
tools
structured_output
embeddings
```

A provider definition may name a credential environment variable. It must never serialize the credential value.

## Request envelope

Conversation requests use a structured envelope:

```text
request_id
conversation_id
messages
model
temperature
max_output_tokens
tools
privacy_requirement
metadata
created_at
```

Supported message roles:

```text
system
user
assistant
tool
```

The envelope validates types, required fields, privacy class, temperature, token limits, and message roles before a provider receives it.

## Response envelope

Provider responses use:

```text
request_id
provider_id
model
content
finish_reason
usage
tool_calls
latency_ms
error
metadata
created_at
```

Raw provider responses should be normalized into this envelope before entering the conversation engine.

## Boundary

The model-provider layer may generate language, proposed tool calls, and structured output.

It does not receive direct authority to:

```text
write files
run shell commands
promote durable memory
approve actions
consume approval tokens
change configuration
```

Those capabilities remain behind deterministic registries and policy gates.
