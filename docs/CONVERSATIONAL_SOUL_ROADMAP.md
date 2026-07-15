# Conversational Soul Roadmap

The Conversational Soul milestone begins a new phase sequence at Phase 1.

## Milestone purpose

Transform Soul from a deterministic command-oriented chat foundation into a coherent multi-turn assistant runtime with bounded tool use, grounded evidence, layered memory, artifact-aware interaction, and a stable but non-canned identity.

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

### Phase 3: Multi-turn conversation runtime

Status:

```text
complete
```

### Phase 4: Conversational orchestrator

Status:

```text
complete
```

### Phase 5: Grounded evidence lifecycle

Status:

```text
complete
```

### Phase 6: Bounded host environment assessment

Status:

```text
complete
```

Deliver:

```text
host.system_status skill
declared read-only command set
structured host evidence
filesystem and block-device provenance
bounded memory, load, network, and systemd summaries
explicit uncollected categories
conversation integration
host-assessment regression tests
```

## Phase 7 — Generic Evidence Follow-up Router

Status: complete

Phase 7 moves evidence follow-up detection, evidence-record selection, claim focus, and deterministic rendering into a reusable router. New evidence-producing skills gain conversational follow-ups from their evidence records without adding skill-specific branches to the orchestrator.

## Phase 8 — Declared Capability Boundaries

Status: complete

Deliver:

    inspectable capability identities
    available, conditional, and unavailable states
    capability-specific conversational routing
    deterministic capability catalog rendering
    explicit no-model-substitute boundaries
    Linux MD RAID and hardware RAID distinction
    regression coverage for host capability declarations

## Phase 9 — Layered Memory Foundation

### Phase 9: Layered memory

Status: complete

Delivered:

    bounded working memory through chat context and digest
    durable project, preference, episodic, and semantic layers
    append-only candidate, approval, supersession, and deletion events
    provenance, confidence, tags, and approved-only retrieval
    reviewed conversational proposal and mutation controls
    approved-reflection import as unapproved memory candidates
    idempotent reflection-import provenance
    replay-verifiable memory snapshot export
    explicit logical-deletion and no-physical-purge policy

Phase 10 is complete.

### Phase 10: Identity, interests, and variation

Status:

```text
complete
```

Delivered:

```text
stable inspectable identity profile
context-sensitive bounded tone modes
bounded recent-assistant-turn style analysis
safe deterministic style inspection
reviewed candidate/approved/inactive/retired interest registry
relevance-gated approved-interest context capped at three records
explicit separation from biography, lived experience, feelings, credentials, embodiment, and authority
combined identity, variation, interest, and hygiene acceptance coverage
```

Phase 11 is in progress.

### Phase 11: Artifact-aware conversation

Status:

```text
in progress
```

Delivered in Phase 11A:

```text
artifact decision policy for explicit deliverables
append-only artifact metadata and lifecycle registry
project-local path and sensitive-state boundaries
source, chat, privacy, media type, size, and SHA-256 provenance
deterministic registration, metadata inspection, attachment, detachment, and archival controls
metadata-only conversation context capped at five attached artifacts
no implied file read, mutation, execution, upload, or deletion authority
```

Delivered in Phase 11B:

```text
attached-only inspection for bounded allow-listed UTF-8 text formats
no-follow exact-byte size and SHA-256 verification before use
deterministic redaction including quoted JSON and assignment secrets
artifact privacy enforcement across local-only, local-network, and cloud providers
untrusted-content labeling before display or model context
explicit ID, title, kind, and bounded reference resolution
visible complete, failed, awaiting-input, and blocked-for-review lifecycle outcomes
provider calls suppressed on ambiguity, failure, and privacy mismatch
bounded structural summaries, excerpts, and two-artifact comparison
no file or registry mutation during inspection
```

Delivered in Phase 11C:

```text
bounded local-model-assisted Markdown, text, and JSON creation
fixed project-local artifacts/ output boundary
revision by new version without source overwrite
non-mutating exact-byte preview with redacted excerpt
scope-bound, expiring, single-use approval token and literal confirmation
exclusive no-follow file creation with post-write size and SHA-256 verification
verified registration, attachment, provider, chat, and revision provenance
visible failure, cancellation, race, privacy, integrity, and registry-recovery behavior
no cloud fallback, upload, export, deletion, move, rename, or in-place edit
```

Remaining:

```text
Phase 11D shared workspace projection and artifact inbox/delivery
```

Deferred beyond the current artifact milestone:

```text
voice input/output behavior
provider export integration
rich document and media handling
in-place edit, move, rename, delete, and cross-system delivery
```

### Phase 11D: Shared workspace and artifact inbox

Status:

```text
implementation authorized; candidate work in progress
```

Planned:

```text
interface-independent workspace projection over canonical artifact identities
bounded workspace and inbox queries
synchronous idempotent artifact delivery records
chat, task, revision, privacy, digest, and lifecycle provenance
seen and dismissed inbox state without artifact mutation
concise deterministic completion and failure summaries
no dashboard, listener, watcher, background process, upload, export, or file mutation
```

Candidate delivered in Phase 11D:

```text
canonical artifact workspace projection capped at fifty records
append-only private inbox delivery and state events
synchronous idempotent Phase 11C completion delivery
explicit current-chat delivery for active attached artifacts
seen and dismissed state without artifact lifecycle or file mutation
revision and delivery provenance validation
provider privacy filtering before workspace model context
deterministic workspace controls with explicit terminal outcomes
truthful artifact completion when inbox append fails
no dashboard, listener, watcher, service, polling, export, or file mutation
```

### Phase 12: Interface contract

Phase 12 is split into bounded vertical slices:

```text
12A portable typed configuration
12B in-process application API contracts
12C foreground loopback dashboard and first human visual review
12D guided Skill Studio as the second primary tab
12E unified approvals and activity views
```

Phase 12A candidate implementation now provides:

```text
canonical typed schema for 21 interface-relevant settings
CLI override → process environment → ignored .env → safe-default precedence
bounded non-interpolating .env parsing without caller-environment mutation
redacted show, explain, and validate commands
provider compatibility projection for Chat
explicit source, validation, privacy/risk, and restart metadata
inert loopback-only dashboard host and port reservation
no listener, service, watcher, polling, provider probe, or configuration write
```

Human merge review remains required before Phase 12A is accepted.

Phase 12B candidate implementation now provides:

```text
versioned soul.application.v1 request and response envelopes
23 explicitly registered in-process operations
bounded Chat, workspace, inbox, configuration, status, skill, approval, and activity projections
shared CLI/application Chat exchange service
append-only private duplicate-send receipts without duplicated chat content
manual-only system-status refresh
redacted non-authorizing approval and activity summaries
no HTTP transport, listener, frontend, service, watcher, scheduler, or polling
```

Human merge review remains required before Phase 12B is accepted.

The dashboard product shape begins with:

```text
Tab 1: Chat
Tab 2: Skill Studio
shared workspace alongside Chat
manual system-status refresh with host identity and timestamp
explicit provider, privacy, approval, task, and failure state
```

Core interface contracts cover:

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

The first dashboard aesthetic must use the existing Soul/ imagery, colorway, typography, and arcane-technical visual language as inspiration. The locally runnable first visual slice pauses for human review before secondary interface features expand. See `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`.

The public repository must not require the owner's IP addresses, hostnames, credentials, model alias, or filesystem paths. CLI, dashboard, tests, and later deployment share one typed configuration contract resolved from CLI overrides, process environment, ignored local `.env`, and tracked safe defaults.

### Phase 13: Integrated acceptance and closeout

Deliver:

```text
automated scenario suite
manual twenty-turn conversation test
skill invocation and return test
grounded host-assessment test
artifact workflow test
memory continuity test
safe failure test
variation test
approval-gated mutation regression
documentation and curation closeout
```

Phase 13 is the clear stopping point.

Proxmox is not required for Phases 11D through 13. A separate human-approved deployment brief follows successful local dashboard acceptance and defines the persistent-service exception, guest topology, environment file, LAN boundary, backup, recovery, upgrade, and rollback behavior.
