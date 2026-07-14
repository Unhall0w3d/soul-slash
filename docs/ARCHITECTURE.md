# Architecture

Soul/ is split into layers. The layers are deliberately separated so conversation can remain flexible while actions remain inspectable and bounded.

## Interface layer

Human-facing inputs and outputs:

- CLI chat
- single-shot CLI messages
- future HTTP API
- future integrated web chat
- future inbox and file space
- future voice input
- future TTS output

Every interface should use the same assistant runtime. Voice and web clients must not grow separate brains.

## Conversation layer

The conversation layer manages:

- current dialogue
- active subject
- active task
- unresolved questions
- recent skill results
- artifacts produced
- pending approvals
- conversational response composition

The current repository contains a deterministic chat foundation. The Conversational Soul milestone will add model-backed multi-turn interpretation and response generation without discarding deterministic safety boundaries.

## Orchestration layer

The orchestration layer decides whether a message should:

- receive a direct conversational response
- continue an existing discussion
- retrieve relevant memory
- ask for clarification
- invoke one skill
- invoke a bounded sequence of skills
- create an artifact
- request approval
- stop because the request is unsafe or unsupported

Current pieces include:

- deterministic intent routing
- workflow sessions
- skill invocation planning
- execution adapter registry
- approval token controls
- selection and confirmation parsing
- response rendering

The conversational orchestrator uses model reasoning for interpretation and synthesis while validating proposed tool use against registered capabilities and risk policy.

## Model and provider layer

Models handle language-heavy, low-risk work such as:

- conversation
- summarization
- rewriting
- intent interpretation
- planning
- result explanation
- draft generation

Models do not receive automatic authority to mutate files, execute shell commands, promote memory, or alter configuration.

Provider selection must preserve:

- capability declaration
- privacy classification
- timeout and failure handling
- local versus cloud visibility
- audit metadata
- graceful fallback

## Execution layer

The execution layer contains deterministic skills and adapters.

Current bounded capabilities include:

- `system.status`
- `downloads.inspect`
- `downloads.cleanup_plan`
- `downloads.move_to_trash`
- execution-history inspection and controls
- approval-token management

Execution skills should produce structured results and explicit verification fields.

Write-capable execution must preserve:

```text
plan
-> approval
-> execute
-> verify
-> history
```

## Artifact layer

Artifacts are durable or reviewable outputs that should not be dumped wholesale into conversation.

Examples:

- reports
- code
- overlays
- CSV or spreadsheet output
- research notes
- implementation plans
- review packages

Phase 11A gives artifacts a shared metadata and conversation-attachment contract. Registered artifacts retain:

- stable artifact identity
- source conversation and source kind
- creator provider or skill when known
- creation and update times
- privacy classification
- lifecycle state
- project-relative file path
- media type, byte size, and SHA-256 digest
- attached conversation IDs

Artifact attachment injects metadata only. It does not grant permission to read, rewrite, move, execute, upload, or delete the underlying file.

Phase 11B adds an explicit bounded inspection path for attached text artifacts. It verifies the exact bytes read against registered size and SHA-256 metadata, applies format and size limits, redacts recognized secrets, and labels all excerpts as untrusted data. Artifact privacy deterministically restricts both metadata and content before either enters provider context. Ambiguity, integrity failure, and privacy mismatch stop before provider invocation.

## Reflection layer

The reflection layer turns task logs into candidate lessons and rules.

Reflection does not automatically promote durable changes.

Current flow:

```text
task log
-> reflection candidate
-> human review
-> approve or reject
-> approved rules and lessons
```

## Memory layer

Soul requires several memory classes:

- working memory for the current conversation
- episodic memory for prior events and completed work
- semantic memory for stable learned facts
- preference memory for user and workflow preferences
- project memory for milestones, decisions, constraints, and current state

Current human-readable memory and rule files live under:

```text
Soul/memory/
```

Current approved rule files include:

```text
Soul/memory/approved_rules.md
Soul/memory/approved_lessons.md
```

Future durable memory must retain provenance, confidence, editability, and promotion status.

## Policy and audit layer

Policy applies across conversation, providers, memory, artifacts, and execution.

It includes:

- risk classification
- privacy boundaries
- provider restrictions
- approval requirements
- token scope and expiry
- runtime-only data rules
- execution history
- human review gates

The policy layer exists so personality and reasoning can be flexible without making state changes mysterious.
