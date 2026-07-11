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
in progress
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

Status: in progress

This implementation slice establishes the durable memory contract before conversational mutation controls are exposed.

Delivered in this slice:

    working memory remains bounded chat context and digest
    durable project, preference, episodic, and semantic layers
    append-only event ledger
    candidate and explicit approval states
    provenance and confidence
    bounded approved-only retrieval
    supersession and logical deletion
    conversation context integration
    no automatic model promotion

Reviewed controls delivered in the next slice:

    reviewed conversational proposal, inspection, approval, supersession, and forgetting controls
    exact conversation provenance and chat identity
    candidate-only remember commands
    confirmation-gated supersession and logical forgetting
    deterministic no-model mutation routing

Remaining Phase 9 work:

    reflection candidate import
    export, backup, and physical purge policy

### Phase 10: Identity, interests, and variation

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

### Phase 11: Artifact-aware conversation

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
