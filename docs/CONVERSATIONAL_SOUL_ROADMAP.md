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

Phase 11 is complete.

### Phase 11: Artifact-aware conversation

Status:

```text
complete
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
complete
```

Approved scope:

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
12D.2 bounded capability-gap intake from Chat to Skill Studio
12D.3 bounded environment and capability assessment in Self Improvement
12E unified approvals and activity views
```

Phase 12A provides:

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

Phase 12A was reviewed and merged.

Phase 12B provides:

```text
versioned soul.application.v1 request and response envelopes
43 explicitly registered in-process operations after later interface slices
bounded Chat, workspace, inbox, configuration, status, skill, approval, and activity projections
shared CLI/application Chat exchange service
append-only private duplicate-send receipts without duplicated chat content
explicit system-status refresh operation
redacted non-authorizing approval and activity summaries
no HTTP transport, listener, frontend, service, watcher, scheduler, or polling
```

Phase 12B was reviewed and merged.

Phase 12C provides:

```text
dependency-free, foreground, sequential loopback HTTP transport
exact static and same-origin JSON route allowlist over soul.application.v1
Host, Origin, ephemeral CSRF, CSP, no-store, and bounded-request protections
branded three-rail Chat workspace with conversation continuity and composer
shared artifact metadata, inbox summary, one initial host-status collection, and explicit manual refresh
visible but behaviorally inert Skill Studio preview as the second primary tab
no daemon, service, worker, LAN bind, polling, remote asset, or persistence install
```

Phase 12C's initial visual-review gate was satisfied by the owner. Its historical brief and assessment retain the original gate language; later phases made Skill Studio functional and added Self Improvement.

Phase 12D provides the controlled Skill Studio lifecycle:

```text
Proposal, Beta, and Production inventories
exact-revision human Gate 1 before Beta implementation work
isolated unregistered Beta candidates
bounded human-invoked Beta diagnostics and test evidence
exact-tested-revision human Gate 2 before later promotion
no automatic Codex invocation, implementation, registration, promotion, merge, or release
```

Phase 12D was visually reviewed and merged.

Phase 12D.2 candidate implementation adds a bounded self-skilling intake bridge:

```text
declared unavailable capabilities and conservatively validated model-reported gaps
production and runnable-Beta coverage checks before proposal creation
deduplicated local-only proposal intake packets
local-private current-chat artifact registration and inbox delivery
automatic Skill Studio visibility with origin, classification, and occurrence count
no silent Mistral call, Codex invocation, implementation, registration, or promotion
both existing human gates preserved
```

Phase 12D.2 was reviewed and merged with both existing human gates preserved.

Phase 12D.3 candidate implementation adds a third Self Improvement tab:

```text
one automatic lightweight environment snapshot when the tab is opened
explicit foreground update, model-runtime, and capability assessment scopes
bounded command timeouts, output limits, and model-file inventory
language/tool versions, package-manager evidence, capability health, and recommendations
preview-first exact-confirmation generation of advisory improvement proposal packets
no package mutation, privileged command, service change, model download, implementation, or promotion
```

Phase 12D.3 passed visual/product review and was merged.

Phase 12D.4 is an owner-requested Skill Studio lifecycle amendment. It derives one visible proposal stage from existing gates, Beta implementation and tests, and exact production registry linkage. The Beta manifest's exact `skill_id` links proposal, Beta, and production. A preview/digest/confirmation closeout may permanently delete the proposal and superseded Beta candidate only after that exact skill is registered in production; the production skill, registry, shared diagnostics, and unrelated data remain untouched. The owner approved this lifecycle presentation with Phase 12E.

Phase 12C.1 adds the owner-approved personal dashboard authentication boundary. A fixed `admin` account begins with the public `soul123` bootstrap credential but cannot access dashboard data until a private replacement password is set. Credentials remain in ignored owner-only runtime storage; sessions persist across dashboard restarts for at most seven days using stored token digests rather than raw bearer tokens. Sign-ups and multi-user roles remain unavailable. Authentication passed first-login review and was merged.

The separately approved protected local deployment keeps Soul on `127.0.0.1:4567` and uses two bounded systemd user services to expose Caddy HTTPS on one exact LAN address and unprivileged port. The operator completed Caddy installation, narrow firewall configuration, private-CA client trust, and remote login/logout review. Internet exposure, router forwarding, wildcard binding, and automatic firewall mutation remain out of scope. The deployment passed review and was merged.

An owner-approved Phase 12C usability amendment adds preview-first conversation-list clearing by exact title, a human-selected set of exact active chat IDs, or all active conversations. Clear means reversible metadata archival, not transcript deletion. Execution requires an exact confirmation and the unchanged preview digest; a stale selected set blocks before mutation.

The dashboard product shape is:

```text
Tab 1: Chat
Tab 2: Skill Studio
Tab 3: Self Improvement
shared workspace alongside Chat
initial and manually refreshed system status with host identity and timestamp
explicit provider, privacy, approval, task, and failure state
```

Phase 12E adds the owner-approved unified Review Center as a header-level supporting surface rather than a fourth primary tab. It composes the existing redacted pending-approval and recent-activity projections, provides bounded manual refresh and activity filters, and exposes no token value, private request, approval mutation, retry, replay, clear, prune, or export action.

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

The dashboard aesthetic uses the existing Soul/ imagery, colorway, typography, and restrained arcane-technical visual language. Material interface changes continue to require human review. See `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`.

The public repository must not require the owner's IP addresses, hostnames, credentials, model alias, or filesystem paths. CLI, dashboard, tests, and later deployment share one typed configuration contract resolved from CLI overrides, process environment, ignored local `.env`, and tracked safe defaults.

### Phase 12D.5: Gated implementation and production promotion

Complete the Skill Studio lifecycle with two bounded foreground operations: build an approved exact proposal revision into an isolated Beta candidate for review, then promote an exact tested and Gate-2-approved Beta revision into the production registry through preview, digest revalidation, exact confirmation, rollback evidence, and human review. Model or cloud output remains candidate material and cannot authorize either operation.

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
