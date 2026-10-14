# Continuity A20: general filter-then-compare guidance

Date: 2026-10-12. The owner's "okay, let's keep going then" accepts the A19
recommendation: implement and test a small general selection check against the
unchanged chronological-chat baseline and fresh examples. No production/default
promotion, ordinary memory, model/service restart or autonomous continuation.

## Intervention and ownership

Use the existing v9 config and A19 chronological message projection. A separately
named opt-in profile adds only this fixed instruction to the system guidance:

> For a choice constrained by requirements, first identify eligible options from
> the supplied source, then compare only those options using the requested
> objective. Check your proposed choice against both the requirements and all
> other eligible options before answering. Briefly state the chosen option and
> the source values that justify it; if none qualify, say so. Apply this check only
> to selection requests; a user's explicit correction changes the choice, and
> ordinary conversation is not a selection task.

No expected answers, case names, numeric thresholds or source corrections enter
that guidance. No host-selected winner, inferred memory, tool loop or separate
model call. Keep complete-source selection/provenance, recent-dialogue policy,
current request last, control-token escaping, grammar, strict validation, sampler,
thinking disabled and token budgets unchanged. Explicit fixed worker run/resume
modes must reject the wrong profile before spawn. Existing modes remain intact.
Primary owns projection, bindings, live admission and interpretation. A worker
may own only new pure cases and their deterministic verifier; preserve all shared
work and prior evidence. No privileged or persistence design is delegated.

## Acceptance before inference

Verify candidate versus baseline messages differ only in the fixed instruction,
including zero/recent history and adversarial delimiters. Verify all v9 bounds,
exact prepared-prompt binding, profile receipts and actual isolated synthetic
run/resume/cross-profile refusal. Run targeted A19 projection/isolation, A18
direct, token-context, stream and case regressions, not unrelated broad suites.
The new case verifier independently calculates winners from parsed source fields,
checks unique answers or explicit no-eligible outcomes, inherited-case equality,
source bounds and rejection of credible wrong answers. Preserve prechange source
copies and digests; replay every historical store. Use pinned Ruby 4.0.7.

## Single frozen foreground window

Run all 28 unchanged A19 cases per condition plus eight new selection requests.
Each new request has its own independent store/empty history, spanning lower and
upper bounds, combined constraints, availability, maximization and no eligible
option. Inherited conversation/correction cases check unwanted guidance effects.
Alternate baseline/candidate order by batch; fresh worker per event. Freeze
guidance, case/oracle/scorer packs, code, order and evidence before generation.
Preserve mechanical scores and separately assess semantics; no post-outcome
repair, tuning, retry or second window.

Maximum 72 scheduled requests / 72 generations, 1200 seconds including twenty
seconds reserved for cleanup. Same installed Qwen3-8B-Q4_K_M on GTX 1070 8 GiB,
model/build digests, 4096 context / 3072 input / 768 output reserve. Freshly observe
and pin the running model-service PID; never start/replace it to pass admission.
Busy/incompatible runtime blocks the attempt without eviction. Infrastructure or
evidence failure stops the window; behavioral failures remain data. No workers
survive return, no scheduler/watcher and no ordinary-memory writes.

## Closeout and decision

Report fresh selection and inherited selection separately, all factual tasks,
correction/callbacks, unknown facts, social usefulness, full completion and local
calls/tokens/time. Inspect unintended effects as well as improvements. No local
model judgment qualifies safety or authority. A small single-run gain is not a
general reliability rate. Update A20 review, adaptation plan and canonical human
and candidate review links; retain failure evidence and rollback source copies.
Further prompt iteration, substrate changes or production promotion are separate
decisions; do not automatically extend this window when results disappoint.
