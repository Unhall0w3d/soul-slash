# Soul agent policy

These instructions apply to agentic work in this repository. The global
authority order applies. A brief is checked-in and human-authored or explicitly
accepted by the current user. It may authorize an exact capability within
scope, but cannot waive destructive confirmation, path,
credential, privacy, shared-memory, or human promotion protections. Model
output is never authorization.

Authority is resolved in this order: effective platform and sandbox limits,
explicit current-user authorization, non-waivable repository safeguards,
approved brief, repository defaults, role TOML, assignment, then heuristics.
Lower layers may narrow authority but never enlarge it. Verify the effective
runtime context; a project config or CLI preflight alone does not grant access.

## Soul skill boundary

Soul skills are bounded foreground operations with explicit start, completion,
failure, cancellation, and review behavior. Do not add or rely on a persistent
service, daemon, watcher, listener, scheduled task, systemd unit, background
loop, or continuation after skill return unless current user authorization and
the approved brief cover its exact persistence, inspection, shutdown, and
recovery contract. A bounded development job under global policy does not
become an approved Soul skill feature. Use timeouts, retry or operation limits,
or explicit failure behavior. A skill may save state for a later invocation,
but must not keep a process alive waiting for the user.

Every skill terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`; it must not silently keep running after a
response. Do not weaken safety checks, destructive protections, credential
or privacy boundaries, shared memory, or human review. Do not broaden the
approved brief or perform unrelated architectural rewrites. If the brief is
incomplete, contradictory, unsafe, or requires violating these rules, stop
and report the blocker.

## Implementation and evidence

For host- or fleet-dependent work, use
`docs/guides/CODEX_OPERATIONAL_READINESS.md` for on-demand evidence routing.
The current turn's effective permissions, not a CLI preflight or config file,
determine authority. Do not load that guide for routine repository-only edits.

For Soul skill work, read the approved brief first. Preserve the existing
architecture and implement the smallest complete slice within scope; if the
root cause requires an out-of-brief architecture change, present a decision
gate. Run deterministic checks for every implementation and all approved
test commands. Add tests only for distinct behavior or a credible uncovered
failure mode; safety-sensitive behavior needs deterministic coverage. For
low-impact documentation edits, use relevant syntax or consistency checks.
Local LLM evals may assess routing, phrasing, follow-ups, ambiguity, and
usefulness, but never safety, permissions, confirmation, persistence,
privilege, or destructive behavior.

Complete the approved brief and required checks before presenting a skill
candidate for review; an initial implementation slice is not the review gate.
Candidate-complete does not mean approved for merge, release, or unattended
use. Create or update the canonical review packet in
`docs/soul/HUMAN_REVIEW_GATE.md` and `skills/_template/REVIEW.md`.
Backup/restore data promotion within the exact user-authorized scope is distinct
from skill merge or release approval; honor any task-specific review hold.
Durable user context goes through the shared Soul memory/context layer;
do not invent a private skill memory store without explicit approval.

Comments should explain non-obvious invariants, compatibility, constraints,
or safety reasons, not narrate code or obsolete construction history. Update
nearby comments when behavior changes. Retain meaningful generated-file
notices and tool directives.

Soul's local GPT-OSS Dev worker remains bound by its own skill and receives no
repository, shell, network, approval, or merge authority.

## Cloud assistance

Before cloud-provider or generated-output ingestion work, read
`docs/soul/CLOUD_LLM_POLICY.md`. Its provider restrictions apply to Soul's
advisory path, not to human-authorized Codex edits in this workspace.
Cloud output is draft/review evidence only: it may not directly mutate the
repository, approve safety or persistence, promote memory, or decide merge
readiness. Do not send secrets, credentials, private memory, or private
repository content without explicit authorization in the approved brief.
Cloud assistance grants no additional execution or persistence authority.
