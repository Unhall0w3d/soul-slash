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

Phase 10 is in progress.

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

Remaining:

```text
bounded artifact creation and revision
attachment inbox and delivery
voice-friendly completion summaries
richer lifecycle and provider export integration
```

### Phase 12: Interface contract

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
