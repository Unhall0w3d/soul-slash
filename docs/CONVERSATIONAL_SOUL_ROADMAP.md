# Conversational Soul Roadmap

The Conversational Soul milestone begins a new phase sequence at Phase 1.

## Milestone purpose

Transform Soul from a deterministic command-oriented chat foundation into a coherent multi-turn assistant runtime with bounded tool use, layered memory, artifact-aware interaction, and a stable but non-canned identity.

### Phase 1: Architecture and acceptance contract

Status:

```text
complete
```

### Phase 2: Provider and model capability foundation

Status:

```text
complete
```

Delivered:

```text
provider-neutral request and response envelopes
provider capability and privacy metadata
local OpenAI-compatible provider shape
local Ollama provider shape
disabled cloud-compatible shape
bounded health checks
timeout and failure normalization
```

### Phase 3: Multi-turn conversation runtime

Status:

```text
in progress
```

Deliver:

```text
model-backed session loop
recent-turn context
active subject and task hints
bounded context digest
provider fallback
deterministic action preservation
runtime conversation state
session persistence
```

### Phase 4: Conversational orchestrator

Deliver:

```text
direct-answer decision
memory-retrieval decision
single-skill decision
bounded skill-chain decision
artifact decision
approval decision
tool relevance validation
loop and stop limits
result synthesis
```

### Phase 5: Layered memory

Deliver:

```text
working memory
project memory
preference memory
episodic memory
semantic memory
provenance
confidence
candidate promotion
supersession
inspection and deletion
```

### Phase 6: Identity, interests, and variation

Deliver:

```text
stable personality principles
context-sensitive tone
recent-style awareness
overuse detection
inspectable interests
no joke quotas
no fabricated biography or embodiment
```

### Phase 7: Artifact-aware conversation

Deliver:

```text
artifact decision rules
artifact metadata
conversation attachment
inbox delivery
voice-friendly summaries
file lifecycle
provider and source provenance
```

### Phase 8: Interface contract

Deliver designs and core API contracts for:

```text
Chat
Inbox
Files
Activities
Approvals
Skills
Memory
Settings
System status
```

### Phase 9: Integrated acceptance and closeout

Deliver:

```text
automated scenario suite
manual twenty-turn conversation test
skill invocation and return test
artifact workflow test
memory continuity test
safe failure test
variation test
approval-gated mutation regression
documentation and curation closeout
```

Phase 9 is the clear stopping point.

## Work deferred beyond this milestone

```text
polished dashboard implementation
full voice implementation
broad cloud-provider catalog
large skill library
Proxmox deployment profile
backup and restore automation
mobile clients
```
