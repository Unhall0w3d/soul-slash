# Reviewed Memory Ledger Bootstrap A6 Review

Status: Candidate-complete; live projection requires the Operator's exact
digest-bound execution gate.

## Implemented

- A fixed-source, foreground preview over `approved_rules.md` and
  `approved_lessons.md`.
- Content-free source, record, and plan digests for review.
- Exact-confirmation, stale-plan rejection, append-only proposal and approval,
  idempotent repetition, interrupted-candidate recovery, and lifecycle-conflict
  blocking.
- A reusable CLI and Make targets. No arbitrary path or content input exists.

## Files changed

- `docs/soul/MEMORY_REVIEWED_LEDGER_BOOTSTRAP_A6_BRIEF.md`
- `lib/soul_core/reviewed_memory_ledger_bootstrap_service.rb`
- `scripts/memory-reviewed-ledger-bootstrap.rb`
- `scripts/verify-memory-reviewed-ledger-bootstrap-a6.rb`
- `docs/assessments/MEMORY_REVIEWED_LEDGER_BOOTSTRAP_A6_REVIEW.md`
- `Makefile`

## Verification

- `ruby -c lib/soul_core/reviewed_memory_ledger_bootstrap_service.rb`
- `ruby -c scripts/memory-reviewed-ledger-bootstrap.rb`
- `ruby -c scripts/verify-memory-reviewed-ledger-bootstrap-a6.rb`
- `ruby scripts/verify-memory-reviewed-ledger-bootstrap-a6.rb`
- `ruby scripts/memory-reviewed-ledger-bootstrap.rb preview`
- `git diff --check`

The deterministic verifier covers preview privacy, fixed sources, missing and
incorrect confirmation, source drift, successful projection, event lifecycle,
idempotence, interrupted-candidate recovery, lifecycle conflict, and symlink
rejection.

## Lifecycle and memory

Touched terminal states: `complete`, `awaiting_input`,
`blocked_for_human_review`, and `failed`.

Successful live execution adds semantic records to the existing shared
append-only conversation-memory ledger. It creates no separate memory store and
does not rebuild disposable retrieval state.

## Risks and limitations

- Markdown parsing intentionally admits only top-level single-line bullets.
- Execution is append-only and safely resumable, but not filesystem-transactional;
  an interruption may require a fresh preview before resumption.
- Only the two files whose names and workflow already establish owner review are
  eligible. Private YAML and unapproved lessons remain excluded.
- This slice does not qualify or start an embedding runtime and does not author
  the private retrieval cases.

## Human checklist

- Confirm the preview reports exactly 22 reviewed rules and 10 reviewed lessons.
- Confirm no private content is present in the preview.
- Execute only the current digest with `IMPORT_REVIEWED_MEMORY_LEDGER`.
- Refresh Memory Observatory and confirm 32 approved semantic records.
- Author the ignored private retrieval cases from the resulting memory IDs.
