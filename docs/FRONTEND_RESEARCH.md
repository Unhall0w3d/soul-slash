
# Frontend Research Notes

Soul will build its own required interaction layer, but existing open-source projects are useful reference points.

## Open WebUI

Useful concepts:

```text
self-hosted web chat
model/provider configuration
tool/function extension points
conversation history
local and cloud model support
```

Soul posture:

```text
optional future frontend
not required
not the source of truth for skills, policy, or memory
```

## LibreChat

Useful concepts:

```text
conversation search
multi-provider routing
agent/tool configuration
import/export
web-first UX
```

Soul posture:

```text
good UX reference
too large to become Soul's mandatory control layer
```

## LobeChat

Useful concepts:

```text
clean UI
provider abstraction
plugins/agents
knowledge-base style workflows
voice-adjacent interaction patterns
```

Soul posture:

```text
strong design inspiration
possible optional client
not required infrastructure
```

## AnythingLLM

Useful concepts:

```text
workspace organization
document context
local-first positioning
agent/document pipeline integration
```

Soul posture:

```text
useful comparison point
not a direct fit for Soul's skill governance model
```

## Lessons to borrow

Soul should support:

```text
new chats
recent chats
pinned chats
chat search
projects/workspaces
human-readable skill catalog
message history
structured attachments/artifacts later
model/provider selection later
voice later
```

## Lessons to avoid

Soul should avoid:

```text
making a third-party UI mandatory
burying skill execution in opaque tool calls
letting a frontend define memory semantics
letting model chat replace deterministic skill execution
shipping a web stack before terminal chat works
```

## Chosen direction

Build Soul's own interaction core.

Later, expose APIs so external frontends can become optional clients.
