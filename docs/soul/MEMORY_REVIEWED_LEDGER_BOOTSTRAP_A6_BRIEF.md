# Reviewed Memory Ledger Bootstrap A6 Brief

Status: Operator-approved implementation scope, 2026-08-23

## Objective

Populate an empty canonical conversation-memory ledger from the two existing
owner-reviewed memory sources so semantic retrieval can be qualified against
real approved records.

This is a one-time, bounded foreground projection. It does not infer new
memory, read draft lessons or private YAML, start a model, rebuild an index, or
run in the background.

## Fixed sources

Only these regular non-symlink files are eligible:

- `Soul/private/memory/approved_rules.md`
- `Soul/private/memory/approved_lessons.md`

Each top-level Markdown bullet becomes one canonical semantic-memory record.
Blank bullets, nested bullets, headings, prose outside bullets, and entries
longer than 1,000 characters fail safely. Each source is capped at 64 KiB and
the combined projection is capped at 64 records.

## Preview and execution

Preview returns only source IDs, byte counts, SHA-256 digests, projected record
counts, existing-record counts, content digests, a confirmation phrase, and a
digest of the complete fixed plan. It does not return memory content.

Execution requires the exact phrase `IMPORT_REVIEWED_MEMORY_LEDGER` and the
current preview digest. It recomputes the plan, rejects drift, proposes each
record through the shared append-only memory store, and immediately records an
approval transition because the source files are already owner-reviewed.

Every record carries a deterministic import key. Repeating the exact operation
skips already approved records. A matching candidate left by an interrupted
run may be completed; superseded, deleted, or conflicting records block the
operation for human review.

## Boundaries

- No arbitrary path, Markdown, layer, source, tag, or memory content is accepted.
- No existing record is edited, superseded, deleted, or forgotten.
- No private source content is returned by preview, execution, logs, or receipts.
- No index rebuild, model load, Core transition, network request, retry loop,
  watcher, service, timer, or background continuation is permitted.
- Terminal states are `complete`, `awaiting_input`, `blocked_for_human_review`,
  or `failed`.

## Acceptance

- Fixed-source containment, symlink, type, size, encoding, and Markdown-shape
  checks fail safely.
- Preview is non-mutating and content-free.
- Execution is digest-bound, exact-confirmation gated, idempotent, and uses the
  shared canonical ledger.
- Only projected records receive approval transitions.
- Deterministic tests cover drift, repetition, interruption recovery, conflict,
  and privacy boundaries.
