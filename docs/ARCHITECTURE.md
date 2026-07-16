# Architecture

Soul/ is split into layers. The layers are deliberately separated so conversation can remain flexible while actions remain inspectable and bounded.

The optional local deployment preserves this separation: Soul's HTTP application remains bound to loopback, while an independently configured Caddy user service terminates LAN HTTPS and forwards only to the loopback endpoint. One exact `dashboard.public_origin` expands browser Host/Origin validation without granting a LAN bind to Soul itself.

## Interface layer

Human-facing inputs and outputs:

- CLI chat
- single-shot CLI messages
- foreground loopback dashboard over the versioned application facade
- dashboard Chat, Skill Studio, and Self Improvement tabs
- shared workspace and inbox metadata inside Chat
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

The repository now contains persistent model-backed multi-turn conversation, deterministic capability boundaries, evidence follow-up routing, layered memory controls, identity/style context, and artifact-aware responses. Deterministic validation remains authoritative whenever a request reads evidence, invokes a skill, changes state, creates an artifact, or crosses a provider/privacy boundary.

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
- `downloads.restore_last_cleanup`
- `weather.report`
- `chats.clear`
- `chats.forget`
- execution-history inspection and controls
- approval-token management

Separate Beta candidates are held outside the production registry. They run only after preview and exact human confirmation, with bounded foreground execution and local diagnostic evidence.

Phase 12D.5 connects Gate 1 to an honest incomplete proposal-local Beta workspace and bounded Codex handoff without invoking a model. After separate implementation, current passing tests, and Gate 2 approval of the exact digest, production promotion is still a distinct preview/digest/exact-confirmation mutation. It copies one self-contained Ruby entrypoint into a fixed generated-skill directory, atomically adds a new registry entry, writes byte-hash and rollback evidence, and never replaces an existing production skill.

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

Phase 11C adds approval-scoped artifact creation and revision. Phase 11D projects canonical artifact metadata into a shared workspace and append-only conversation inbox without creating an unrestricted filesystem browser.

## Improvement layer

The Self Improvement surface composes existing read-only assessors for the host environment, package managers, language/tool versions, local model runtime, and Soul capability matrix.

Automatic tab-open work is limited to one lightweight read-only snapshot. Deeper checks are explicit foreground requests. Advisory proposal generation requires a preview, exact digest, and human confirmation. Package installation/removal, operating-system updates, service changes, model downloads, implementation, and promotion are not authorized by this layer.

## Unified review layer

Phase 12E composes the existing `ApprovalTokenStore` and `ChatExecutionHistory` through the redacted application-facade projections. Review Center is a supporting dashboard dialog over the three primary tabs. It loads on explicit open or refresh, performs no polling, exposes no authorization values or private request messages, and adds no approve, revoke, consume, replay, retry, clear, prune, or export authority.

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
