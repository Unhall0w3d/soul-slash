# Self Augmentation and Host Improvement Architecture

```text
document_status: approved
implementation_authorized: A1-A3 only
host_mutation_authorized: no
automatic_codex_invocation_authorized: no
persistent_or_privileged_broker_authorized: no
program: Architecture and Stewardship
design_gate: A0
```

## Decision summary

Soul should expose three separate authorities:

| Surface | Subject | Highest authority in the first implementation |
|---|---|---|
| Self Assessment | The host and Soul's operating environment | Observe and create review-only change plans |
| Host Improvement | Packages, runtimes, models, services, and user configuration | Produce exact terminal handoff packets and verify human-executed results |
| Self Augmentation | Soul's tracked source, architecture, contracts, and dashboard | Inspect, propose, and prepare isolated experiments after a human gate |

Skill Studio remains responsible for bounded capabilities. Host Improvement is
not a skill factory, and Self Augmentation is not a larger Skill Studio. A skill
adds a bounded operation inside the current architecture; augmentation proposes
changes to that architecture.

The dashboard should keep `Self Assessment` as the third tab and add
`Self Augmentation` as a fourth tab. Host Improvement appears as a gated section
inside Self Assessment because it acts on the assessed environment. Music is a
separate later product surface and is not part of this architecture.

## Existing Soul primitives to reuse

- `BoundedCommandRunner` for argv-only commands, output caps, timeouts, and
  foreground process-group cleanup.
- `EnvironmentAssessor`, `PackageManagerAssessor`, `RuntimeAssessor`, and
  `ModelRuntimeAssessor` for evidence collection.
- application-facade request IDs, lifecycle envelopes, and activity records.
- preview, current-state digest, exact-confirmation, and revalidation patterns.
- model-runtime leases and control locks for shared-resource safety.
- Skill Studio proposal/Beta/review presentation patterns, without sharing its
  promotion authority or storage roots.
- Codex handoff contracts, allowed/forbidden file declarations, deterministic
  dry-run review, and human review artifacts.
- the existing risk classes in `docs/soul/RISK_CLASSES.md`.

## Boundaries that must remain separate

```text
assessment evidence
≠ mutation authority

LLM proposal
≠ approved plan

approved plan
≠ privilege grant

passing tests
≠ integration approval

Codex candidate
≠ repository change authorized by Soul
```

Dashboard authentication proves access to the private UI. It does not authorize
a host transaction, source change, external push, merge, persistent service,
privileged helper, or destructive action.

## Shared lifecycle contract

Every foreground operation terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

Longer work may persist a resumable record and continue only after a later
foreground invocation. No proposal, experiment, transaction, or review may
leave a process alive waiting for the operator.

Both domains use immutable revision digests. Approving revision N never
authorizes revision N+1.

## Storage and provenance

New generated state remains local and ignored by Git:

```text
Soul/host_improvement/plans/<plan-id>/
Soul/host_improvement/runs/<run-id>/
Soul/augmentation/proposals/<proposal-id>/
Soul/augmentation/experiments/<experiment-id>/
Soul/augmentation/reviews/<review-id>/
```

Each record has a bounded JSON manifest, append-only events, content digests,
timestamps, lifecycle state, source evidence references, and a human-review
flag. Records must use shared Soul runtime/context infrastructure rather than a
skill-private memory store.

Private host paths, package inventories, logs, and uncommitted diffs do not enter
Git or cloud model context. Public design reviews retain schemas, hashes,
bounded summaries, and synthetic fixtures only.

## Host Improvement

### Purpose

Convert read-only assessment evidence into provider-specific, human-reviewable
change plans. The first release stops at an exact terminal handoff and
post-change verification. Soul does not receive, store, proxy, or replay a sudo
password.

### Host plan schema

```text
schema_version
plan_id
revision
created_at
source_assessment_digest
adapter_id
risk_class
title
rationale
preconditions[]
current_state[]
intended_changes[]
exact_argv[]
packages_before[]
packages_expected_after[]
services_before[]
services_expected_after[]
files_expected_to_change[]
download_sources[]
signature_and_digest_requirements[]
estimated_download_bytes
estimated_disk_delta_bytes
expected_duration_seconds
reboot_expected
logout_expected
interruption_policy
recovery_guidance
postconditions[]
verification_commands[]
prohibited_effects[]
human_review_required
```

No shell string is authoritative. `exact_argv` is an array of bounded arrays.
Display text is derived from the same normalized plan but cannot be executed.

### Adapter boundary

Each adapter owns its own policy and verifier. Adapters are not interchangeable:

```text
arch.system_upgrade
arch.package_install
arch.package_remove
aur.rebuild_review
flatpak.update
flatpak.unused_remove
user.runtime_install
user.model_install
user.service_change
```

Initial implementation should support planning and verification only. Execution
authority is added one adapter at a time in later human-authored briefs.

### Arch Linux rules

- Update inventory uses `checkupdates --nocolor`, not `pacman -Sy` and not a
  potentially stale `pacman -Qu` result presented as current.
- A system upgrade plan is one full `pacman -Syu` transaction. Soul must not
  construct partial-upgrade sequences.
- `--nodeps`, `--dbonly`, `--noscriptlet`, `--overwrite`, and unattended
  `--noconfirm` are prohibited unless an exceptional human-authored brief names
  the exact reason and recovery procedure.
- Plans surface foreign/AUR packages, `.pacnew`/`.pacsave` risk, Arch news review,
  package database lock state, free space, current kernel, and reboot likelihood.
- Package removal never treats “orphan” as authorization. Every removal target
  and reverse dependency effect must be listed and confirmed.
- Failure does not trigger an invented automatic downgrade. The transaction
  receipt stops for human recovery review.

These constraints follow Arch's supported full-upgrade model and pacman's own
transaction semantics:

- [Arch checkupdates manual](https://man.archlinux.org/man/checkupdates.8.en)
- [pacman manual](https://man.archlinux.org/man/pacman.8.en)
- [Arch package management guidance](https://wiki.archlinux.org/index.php/Package_Management_FAQs)

### Host lifecycle

```text
read-only assessment
→ candidate plan
→ plan review
→ Gate H1: approve exact plan revision
→ terminal handoff packet
→ operator performs or cancels the transaction
→ import/collect bounded receipt evidence
→ postcondition verification
→ complete / failed / blocked_for_human_review
```

Gate H1 authorizes creation of the terminal handoff, not privilege. The operator
still chooses whether to run the exact command in a terminal and authenticates
there.

### Later privileged execution gate

A dashboard-triggered privileged executor is intentionally deferred. If later
approved, it requires a separately installed, minimal root-owned mechanism with
declared actions, fixed executable paths, strict typed arguments, no shell, and
fresh interactive administrator authorization for each transaction.

Polkit is a possible authorization layer, not a validation layer. Its own
documentation notes that privileged programs must validate their arguments and
that retained authorization can be unsafe when decisions depend on varying
details:

- [polkit action and rule reference](https://polkit.pages.freedesktop.org/polkit/polkit.8.html)
- [pkexec security notes](https://polkit.pages.freedesktop.org/polkit/pkexec.1.html)

Soul must not install such a mechanism from a self-generated proposal.

### Foreground containment

Unprivileged mutation adapters may later use a transient foreground systemd
scope/service with `--wait` and `--collect` to obtain a bounded exit status and
cgroup accounting. They must not use timer/path/socket activation or detached
execution. This is an optional containment implementation, not authorization:

- [systemd-run manual](https://man7.org/linux/man-pages/man1/systemd-run.1.html)

## Self Augmentation

### Purpose

Allow Soul to reason about limitations in its own architecture and produce
reviewable change proposals that are broader than a skill. Soul may inspect its
tracked public source under bounded rules. It cannot inspect secrets, grant
itself permissions, invoke Codex automatically, modify the primary worktree, or
integrate its own candidate.

### Read-only code census

The census starts from `git ls-files -z` at an exact HEAD. It does not walk the
filesystem freely. It rejects symlinks and submodules in the first release and
excludes at minimum:

```text
.env and .env.*
Soul/runtime/**
Soul/**/private or generated local records
models/**
config/secrets/**
.git/**
untracked files
ignored files
worktrees outside the approved experiment path
```

Reads are capped by file count, per-file bytes, total bytes, and elapsed time.
Binary files are metadata-only. The census records HEAD, dirty state, file
digests, language/area summaries, public contracts, verifier coverage, and
bounded dependency metadata. A dirty primary worktree blocks experiment
preparation but not read-only assessment.

### Augmentation proposal schema

```text
schema_version
proposal_id
revision
title
objective
observed_limitation
evidence[]
why_not_a_skill
affected_contracts[]
affected_surfaces[]
allowed_files[]
forbidden_files[]
new_dependencies[]
host_effects[]
persistence_effects[]
security_and_privacy_effects[]
memory_effects[]
data_migration
compatibility_and_interworking
acceptance_criteria[]
deterministic_tests[]
model_capability_tests[]
rollback
open_questions[]
risk_class
human_gates[]
```

The proposal must explain why a bounded production or Beta skill cannot solve
the problem. If that explanation fails, it is redirected to Skill Studio.

### Gates

```text
read-only census
→ augmentation proposal candidate
→ Gate A1: approve exact proposal and experiment scope
→ isolated worktree + bounded implementation handoff
→ human/Codex implementation in that worktree
→ deterministic tests and capability-specific model qualification
→ candidate review dossier
→ Gate A2: approve exact candidate revision for integration consideration
→ explicit external integration action by human/Codex
→ post-integration verification
```

Gate A1 may create one experiment worktree and handoff packet. It does not invoke
Codex. Gate A2 does not merge, push, release, migrate data, enable services, or
apply host changes. Integration is deliberately outside Soul's self-directed
authority.

Class 5 proposals—authentication, privilege, persistent services, destructive
behavior, security boundaries, memory policy, provider privacy, or unattended
execution—require a new human-authored implementation brief even after A1.

### Worktree isolation

Experiments use a clean linked Git worktree at a bounded approved path and an
exact base commit. A detached worktree is appropriate for throwaway assessment;
a named `codex/augmentation-*` branch is created only after the human approves
an implementation candidate. The primary worktree is never the experiment
target.

Git documents that linked worktrees have separate `HEAD` and index state while
sharing repository history, and that cleanup should use `git worktree remove`:

- [Git worktree documentation](https://git-scm.com/docs/git-worktree.html)

Experiment cleanup refuses a dirty worktree. No forced removal occurs from the
dashboard. Stale administrative records are reported for review rather than
silently pruned.

### Model roles

```text
Ministral/local model:
  summarize bounded evidence, identify candidate limitations, draft schemas,
  critique proposals, and explain test results

Codex:
  inspect the explicitly allowed repository slice, implement an approved
  experiment, add tests, and produce a candidate review artifact

Deterministic Soul code:
  enforce paths, digests, gates, lifecycles, locks, test command allowlists,
  provider privacy, and operation receipts

Human operator:
  approve experiment scope, invoke Codex, review the exact diff and evidence,
  authorize integration, and authorize any host or persistent effects
```

No model decides its own risk class, file authority, test sufficiency,
integration readiness, privilege, persistence, or merge approval.

### Candidate dossier

The review dossier contains:

```text
base and candidate commits
proposal and candidate digests
complete changed-file inventory
bounded diff statistics
allowed/forbidden path validation
commands run and exact exit states
deterministic test results
capability-specific local-model results
dependency and license changes
configuration/schema/migration changes
memory keys and privacy effects
host/persistent effects
known weaknesses
rollback instructions
human checklist
```

Passing tests means candidate-complete only.

## Dashboard design

### Self Assessment tab

Keep the current evidence cards and add a `Change Plans` rail:

- assessment evidence with freshness and source;
- host plan candidates grouped by adapter and risk;
- exact before/after inventory;
- preconditions, interruption policy, and recovery notes;
- Gate H1 review;
- copy/open terminal handoff action;
- bounded receipt and postcondition review.

The dashboard never contains a sudo password input. A terminal handoff is shown
as a deliberate boundary, not a failure of integration.

### Self Augmentation tab

Use four visible stages:

```text
Observe → Propose → Experiment → Review
```

Left rail:

- codebase health and exact HEAD;
- proposal queue;
- isolated experiments;
- candidate dossiers;
- integrated/closed history.

Main review surface:

- limitation and evidence;
- “why this is not a skill” decision;
- affected architecture map;
- allowed and forbidden file scope;
- risk/persistence/memory/privacy impacts;
- deterministic and model-specific acceptance matrix;
- worktree status and candidate diff;
- explicit gates with no hidden next action.

Reactive visual behavior may represent real lifecycle states only. No ambient
animation may imply that inspection, Codex work, testing, or integration is
continuing after the foreground operation returns.

## Application API namespaces

Keep the historical read-only `self_improvement.*` operations for compatibility
while adding non-overlapping namespaces:

```text
host_improvement.assessments.*
host_improvement.plans.*
host_improvement.receipts.*
self_augmentation.census.*
self_augmentation.proposals.*
self_augmentation.experiments.*
self_augmentation.reviews.*
```

There is no generic `execute` operation shared across domains. Each future
mutation operation is explicitly allowlisted with its own typed parameters,
preview operation, digest scope, confirmation, risk classification, and receipt.

## Model qualification rule

General chat acceptance does not qualify a model for Host Improvement or Self
Augmentation. Each new adapter and augmentation workflow receives a dedicated
acceptance matrix covering:

- correct intent and domain routing;
- refusal to confuse assessment with execution;
- structured plan/proposal output;
- ambiguity and missing-evidence handling;
- tool selection without unauthorized tool execution;
- multi-step continuity and revision handling;
- honest failure and partial-result language;
- no fabricated host, repository, test, or integration claims.

Deterministic code—not a model—validates safety, paths, commands, confirmations,
privilege, persistence, and destructive boundaries.

## Recommended implementation slices

Implementation status: A1–A3 were approved and merged on 2026-07-16. A4–A5 are
candidate-complete and await human review. The privileged broker remains
unimplemented.

### A1 — Assessment correctness and schemas

- replace pacman update reporting with `checkupdates --nocolor`;
- stop claiming every detected manager has a safe update check;
- add evidence freshness, command status, and unavailable/error distinctions;
- define host-plan and augmentation-proposal schemas;
- add read-only dashboard projections only.

### A2 — Host terminal handoff

- implement one Arch full-upgrade plan adapter;
- preview/digest/Gate H1 only;
- produce an exact terminal packet without executing it;
- import bounded pacman log/package-state evidence after human execution;
- verify postconditions and write a review artifact.

### A3 — Read-only augmentation census

- tracked-file-only census at exact HEAD;
- bounded architecture/capability evidence;
- local proposal drafting and deterministic schema validation;
- redirect skill-sized proposals to Skill Studio;
- no worktree and no Codex invocation yet.

### A4 — Isolated experiment preparation

- Gate A1 exact proposal approval;
- clean-worktree and base-commit validation;
- one bounded linked worktree and Codex handoff contract;
- no automatic Codex invocation or primary-worktree edit.

### A5 — Candidate review and integration handoff

- deterministic diff/test/dependency review dossier;
- capability-specific Ministral qualification;
- Gate A2 candidate approval;
- explicit handoff to human/Codex for commit, PR, merge, and post-integration
  verification; Soul does not integrate itself.

### Deferred — Privileged broker

Consider only after terminal handoff has demonstrated real value and stable plan
schemas. It requires a separate Class 5 brief, threat model, root-owned helper,
interactive authorization, adapter-specific argument validation, and recovery
testing. It is not implied by approval of this architecture.

## Clean stopping point

A3 is the first clean product stopping point: Self Assessment produces correct
host evidence and terminal-ready plans, while Self Augmentation can inspect and
draft architecture proposals but cannot create worktrees or invoke a coding
agent. A4–A5 may then be reviewed together as the isolated implementation path.

## Human decisions requested

1. Approve Self Assessment + Host Improvement remaining one tab, with Self
   Augmentation as a separate fourth tab.
2. Approve terminal handoff—not dashboard privilege—as the first host mutation
   boundary.
3. Approve two augmentation gates plus a separate external integration action.
4. Approve A1–A3 as the next implementation block and stopping point.

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Approved the three-authority design, shared Self Assessment/Host Improvement tab, separate Self Augmentation tab, terminal handoff boundary, two augmentation gates, and A1-A3 implementation block.
Deferred: host execution, privileged broker, worktree creation, automatic Codex invocation, and repository integration
```
