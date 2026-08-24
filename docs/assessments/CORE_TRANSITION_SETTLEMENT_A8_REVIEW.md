# Core Transition Settlement A8 Review

## Outcome

A8 adds one shared, bounded Dashboard reconciliation after an already
successful Core activation. It addresses the two short-lived evidence gaps
observed during A7 live acceptance without retrying a mutation or weakening a
gate.

## Files changed

- `assets/dashboard/dashboard.js`
- `scripts/verify-core-transition-settlement-a8.rb`
- `scripts/verify-core-orchestration.rb`
- `docs/soul/CORE_TRANSITION_SETTLEMENT_A8_BRIEF.md`
- `docs/soul/CORE_ORCHESTRATION_A0_A1_BRIEF.md`
- `docs/assessments/CORE_TRANSITION_SETTLEMENT_A8_REVIEW.md`
- A7 review and current-state documentation

## Lifecycle and risk

The helper remains inside the originating foreground interaction. It performs
at most two authenticated, read-only `core.status` requests at fixed delays,
then terminates. Activation, confirmation, digest, active-work, idle-state,
lease, and Free Core teardown behavior are unchanged.

Risk is low and reversible: read-only UI reconciliation after a separately
authorized mutation.

## Verification

- `ruby scripts/verify-core-transition-settlement-a8.rb` — 6 checks passed.
- `ruby scripts/verify-core-orchestration.rb` — 28 checks passed.
- `node --check assets/dashboard/dashboard.js` — passed.
- A7 lifecycle, A0-A2 Observatory, A3 Chat context, A5 runtime/private review,
  and A6 reviewed-ledger bootstrap regressions passed.
- `git diff --check` — passed.

The live acceptance that motivated A8 used Soul's exact preview/execute path.
It did not simulate or directly start/stop model services.

## Human review checklist

- [x] Confirm that A7 restored Soul-Lite and the embedding endpoint.
- [x] Confirm that Free Core stopped every model lane.
- [ ] Review the bounded status-settlement wording in the live Dashboard.
- [ ] Approve merge.
