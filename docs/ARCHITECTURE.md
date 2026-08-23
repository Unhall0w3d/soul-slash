# Architecture

Soul/ is split into layers. The layers are deliberately separated so conversation can remain flexible while actions remain inspectable and bounded.

The optional local deployment preserves this separation: Soul's HTTP application remains bound to loopback, while an independently configured Caddy user service terminates LAN HTTPS and forwards only to the loopback endpoint. One exact `dashboard.public_origin`—either the assigned IPv4 address or an optional validated private DNS hostname—expands browser Host/Origin validation without granting a LAN bind to Soul itself. Caddy still binds the exact reviewed IPv4 address.

## Interface layer

Human-facing inputs and outputs:

- CLI chat
- single-shot CLI messages
- authenticated dashboard over the versioned application facade
- Chat plus grouped Self Improvement, Creative Studios, and Administration navigation
- Skill Studio, Self Assessment, Self Augmentation, Music Studio, and Visual Studio
- Host Stewardship with a static capability registry, foreground Host Presence,
  read-only Software and Storage Stewards, deterministic retained-evidence
  Incident Narrator, and a separately configured File Steward mutation boundary
- header-level Review Center and manual Core selection
- shared workspace and inbox metadata inside Chat
- explicit Chat push-to-talk through bounded local CPU transcription
- explicit per-message Chat speech through bounded local CPU synthesis

Every interface should use the same assistant runtime. Voice and web clients must not grow separate brains.

Voice Input A0 adds no second conversation path. Browser audio enters one
authenticated, same-origin, CSRF-protected route with independent size and
duration bounds, is normalized through FFmpeg, and is transcribed by the same
pinned CPU whisper.cpp runtime used for music evidence. The temporary audio and
raw recognition output are removed before the transcript is returned. The
Dashboard inserts that transcript and submits it once through the ordinary Chat
form; the transcription service itself never sends a message. Voice therefore
inherits the existing intent, skill, Core, memory, and confirmation boundaries
instead of bypassing them.

Voice Output A0 likewise creates no second assistant path. An eligible completed
Soul message enters one authenticated, same-origin, CSRF-protected route after
an explicit Speak click. A pinned Supertonic 3 process loads on CPU, writes one
request-private WAV, returns its bytes with private no-store headers, and exits.
Temporary text/audio are removed before return. The browser permits one active
playback, revokes its object URL at every terminal outcome, and stops on
navigation or logout. There is no TTS server, automatic narration, GPU lease,
conversation mutation, or memory write.

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
- bounded lookup and evidence-bearing web research
- execution-history inspection and controls
- approval-token management
- proposal/Beta/production skill lifecycle operations
- host, runtime, capability, and storage assessment
- isolated self-augmentation experiment and review operations
- private music and visual project/candidate operations
- bounded Knowledge Vault search, reviewed memory bridges, deterministic
  knowledge-destination reflection, and explicit local conversation-to-note
  proposal planning
- bounded source-attributed local search across repository documentation,
  Knowledge Vault notes, and canonical Music and Visual project briefs, with
  balanced multi-source ranking, exact source-scoped Chat phrases, and a
  deterministic non-authority/quality guard around later model follow-ups

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

The Self Improvement navigation groups three distinct authority domains:

- Skill Studio manages bounded capability proposals, isolated Beta candidates, test evidence, and explicit production promotion.
- Self Assessment composes read-only assessors for the host environment, package managers, language/tool versions, local model runtime, storage/retention, and Soul capability matrix. Its internal operations retain the `self_improvement.*` namespace for compatibility.
- Self Augmentation prepares architecture-level proposals and exact-scope isolated experiments when a skill cannot solve the limitation. Integration remains external.

Automatic tab-open work is limited to one lightweight read-only snapshot. Deeper checks are explicit foreground requests. Advisory proposal generation requires a preview, exact digest, and human confirmation. Package installation/removal, operating-system updates, service changes, model downloads, implementation, and promotion are not authorized by this layer.

## Core and resource layer

Soul separates stable application identity from physical model identity. The `soul-local-chat` alias remains constant while exact-gated Core selection coordinates supported chat and creative resources. A reviewed conversational creative action includes a deterministic Core preflight in its visible scope: active Core, operation-required Core, transfer decision, and reason. The server binds that requirement into the workflow/action digest. One Operator click may authorize the disclosed Core transition and bounded creative operation together; execution revalidates the requirement and delegates the transfer to `CoreOrchestrationService`.

Daily uses Gemma on AMD. AMD-Free and Music use Qwen on NVIDIA. Music generation
temporarily leases AMD for ACE-Step Vulkan; still, image-guided motion, and
native-video generation use their reviewed Vulkan lanes under the same
exclusive creative-resource boundary. Core transitions and model controls
revalidate active application leases and runtime state. Creative models load
for one bounded operation and exit.

No model-initiated or unattended Core switch, always-resident creative model, idle timer, background queue, or unbounded resource poller is part of this layer.

## Creative candidate layer

Music and visual work uses private projects with immutable generation inputs and append-only candidate lineage. A revision creates a successor rather than mutating its source.

```text
brief
-> exact preview and digest
-> bounded generation
-> validated artifact and receipt
-> machine evidence where useful
-> human review
-> keep, revise, reject, bind, trim, export, or package
```

Music generation persists a durable job record so the server-side operation can complete if the Operator changes dashboard pages. This is bounded job continuity, not a general background worker: every job has one preapproved candidate scope, terminal lifecycle, timeout/cancellation behavior, and artifact validation.

Visual candidates may be copied into exact Music candidate lineage. Static
presentation or repetition of one accepted short motion candidate and final
muxing use reviewed artifacts and deterministic media operations. Upload
packaging is local only; network upload and publication remain outside the
current execution layer.

## Unified review layer

Review Center composes the existing `ApprovalTokenStore` and `ChatExecutionHistory` through redacted application-facade projections. It is a supporting dashboard dialog rather than an execution surface. It loads on explicit open or refresh, performs no polling, exposes no authorization values or private request messages, and adds no approve, revoke, consume, replay, retry, clear, prune, or export authority.

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

Owner-specific durable memory and approved rule files live under the ignored
private root:

```text
Soul/private/memory/
```

Current approved rule files include:

```text
Soul/private/memory/approved_rules.md
Soul/private/memory/approved_lessons.md
```

Older installations may retain compatibility sources under `Soul/memory/`
until the digest-bound copy-and-verify migration is explicitly approved. The
runtime cuts over only after every private copy is verified and the migration
marker is written. Public defaults contain no owner-specific state.
The tracked `Soul/memory/.public_seed_v1` marker tells a clean clone to read
those neutral defaults while directing every mutable write to private storage.

Future durable memory must retain provenance, confidence, editability, and promotion status.

An optional owner-private approved-memory index is disposable derived state,
not another authority. It is bound to the current approved-ledger digest,
embedding profile, vector dimensions, and payload digest. One explicit bounded
foreground rebuild atomically replaces it. Missing, stale, malformed,
symlinked, or incompatible state fails closed to the existing approved-only
lexical path. Administration's Memory Observatory projects bounded lifecycle,
relationship, freshness, and diagnostic-ranking evidence without providing a
write operation. Local embeddings are loopback-only and cannot start a runtime,
download a model, switch a Core, or promote memory.

Ordinary Chat consumes semantic retrieval through a narrow adapter. Only a
fresh compatible hybrid result can nominate record IDs, and each ID is re-read
from the canonical ledger in its current approved state. The adapter preserves
always-include and same-chat context and returns the original lexical result
unchanged for every unavailable, stale, fallback, or failed path.

### Optional external knowledge surface

`SOUL_KNOWLEDGE_VAULT_PATH` may point to an external directory of ordinary
Markdown notes. The vault is a human-readable research, decision, and project
surface; it is not another canonical memory store. Obsidian may open the same
directory, but Soul reads the files directly through bounded foreground
operations.

Approved memory can be explicitly projected into a marked generated note.
Conversely, one selected concise note can be imported only as a candidate in
the shared append-only memory ledger. The existing separate approval,
supersession, and forgetting controls remain authoritative. No watcher,
resident index, automatic Git action, or automatic memory promotion is used.

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
