# Optional AMD reviewer: M0 inventory and M1 fake workflow

2026-10-13. The operator approved the reviewed DOCX proposal and amendments in
the System Management conversation, then added immutable revision binding,
explicit unavailable behavior, and separate review-exposure/acceptance events.
This document records that bounded implementation scope; it grants no M2+ work.

## Outcome and boundaries

- M0: read-only GPU/display/Vulkan, model/service, RAM/swap/disk and repository
  inventory. Record limitations rather than changing host state to complete it.
- M1: native Ruby closed request/response contracts, inert durable review records,
  explicit finite lifecycle, a deterministic fake reviewer and a foreground CLI.
  No GPU inference, download, install, network listener, service/startup edit,
  training, primary-model substitution, ordinary memory or journal mutation.
- Preserve existing dirty files, live baseline configuration and all historical
  qualification data. Add reviewer code outside `continuity_lab/`: A22 binds
  existing files there by digest. Reuse its private-directory and canonical-JSON
  primitives without changing their behavior or its journal schema.
- No daemon/automatic retry. Every CLI invocation terminates. Queued data may
  remain until a later explicit invocation; an unfinished lease becomes
  `indeterminate` on explicit recovery after its deadline, never auto-requeued.

## Contracts

Request schema `soul.reviewer.request.v1`: exact string keys `schema`, `review_id`,
`source_event_id`, `source_answer`, `source_revision`, `evidence`,
`evidence_revision`, `question`, `constraints`, `rubric`,
`validation_requirement`, `created_at`, `expires_at`.

IDs are bounded non-path identifiers. `source_revision` is `sha256:` plus the
UTF-8 answer digest; `evidence_revision` hashes the canonical evidence array.
Each evidence entry has `id`, `text`, `sha256` (prefixed), `provenance`, `redacted`.
There is no automatic path/URL resolution. Maximum encoded request 65,536 bytes,
16 evidence entries, 128 retained requests, and one-day request lifetime.
`validation_requirement` is `advisory` or `independent_required`, frozen at
admission. Unavailable review never changes it or establishes validation.

Response has only `review_id`, `verdict`, `findings`, `omissions`. Verdict is
`supported`, `contradicted`, `insufficient_evidence`, or `mixed`. A finding has
`claim`, `evidence_refs`, `confidence` (low/medium/high), `rationale`, and
`proposed_check`. References must exist in the supplied packet; this validates
attribution, not factual correctness. All generated text is untrusted data.
Runtime identity is supervisor-authored, not accepted from response fields.

Completed artifact retains exact request digest, event/answer/evidence revisions,
attempt ID, response, runtime identity/config digest, and completion time. M1
attests only a deterministic fake provider; no model identity is invented.
Historical completion survives source revision changes. Status inspection with
caller-supplied current revisions marks freshness `current`/`stale`; without
them it is `unknown`. Never silently repurpose a review for a new revision.

## State and persistence

`queued -> leased -> running -> completed | failed | canceled | indeterminate`.
Queued requests may also become `canceled` or `expired`. Lease expiry after
reservation/run means `indeterminate`; expired queued work is `expired`.
One fake attempt per review ID, no implicit retries. Same ID + exact request is
idempotent; changed payload conflicts. Late/duplicate output is fenced by exact
attempt ID, active status and deadline. Cancellation wins if committed first.

The root is an explicitly initialized owner-private new directory below an
owner-private parent. Manifest + private lock + atomically committed hash-chained
records are bounded by count and bytes. Stage files from interrupted writes are
retained, never replayed as committed work or silently removed. Strict replay
validates transitions, revisions, metadata and sequence; malformed/symlinked/
hardlinked/foreign state fails closed. Hash chaining detects accidental change,
not malicious same-user replacement or suffix truncation without an external
anchor. It is not an independent signed accountability ledger.

Unavailable runs retain the request and return: `Reviewer unavailable. Request
retained for later review.` They return `may_proceed_without_review` for advisory
requests and `pending_independent_validation` for required ones. Even a completed
fake review does not satisfy independent validation or claim a reviewed answer.
Live M2 must reuse Soul's AMD admission/lease group; M1 creates no GPU lease.

## Visibility and future experiments

M1 is detached record storage only. It does not deliver reviews to Soul. Recorded,
available, encountered, considered, accepted/rejected must remain separate events
in a later approved integration. Host-confirmed delivery establishes exposure,
not understanding; a model-reported disposition is attributed self-report, not
proof of comprehension or durable adoption. No human acknowledgment is required
merely for future availability, but availability is not acceptance.

M2/M3 must measure net corrections including spoiled correct answers, Qwen8
self-review controls, evidence-first review and fresh held-out tasks. Feedback
projection must fit Qwen's unchanged bounded context. No LoRA work in M1. Future
adapter experiments isolate all writable state and compare adapter-active,
adapter-removed-with-consequences, and clean-baseline lineages; deactivation alone
does not reverse historical effects. No game-launch interception is implied.

## Owned deliverables and acceptance

Primary owns `lib/soul_core/reviewer/`, `scripts/soul-reviewer`, this brief,
`docs/assessments/AMD_REVIEWER_M0_M1_REVIEW.md`, and additive canonical review
indexes. A bounded worker may own only `scripts/verify-soul-reviewer-m1.rb`;
primary retains all persistence, authority, host inventory and integration.

Use repository-pinned Ruby 4.0.7. Required checks:

- Ruby syntax for new files; `ruby scripts/verify-soul-reviewer-m1.rb`.
- `ruby scripts/verify-soul-reviewer-recovery-m1.rb`: power-loss cut points,
  fork/lock contention, quotas, unsafe files, recovery, stale/late completion.
- CLI fixture smoke (initialize/enqueue/unavailable/run/status/reopen), no model.
- Existing `verify-continuity-lab-core-a0.rb`,
  `verify-continuity-lab-recovery-a0.rb`,
  `verify-continuity-lab-chat-gateway-a22.rb` for reused boundaries.
- Changed-path required-check resolver and relevant resulting checks; diff check.
- Preserve before/after hashes of existing Continuity source and host baseline
  config; report live observation separately from deterministic qualification.

Update `docs/soul/HUMAN_REVIEW_GATE.md` and `skills/_template/REVIEW.md` only after
implementation and validation. Candidate-complete M1 does not authorize M2,
LibreChat connection, merge/release, unattended use or training.
