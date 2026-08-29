# Operator DRS Stream Reconciliation A0 Review

Status: candidate-complete; human merge and live reconciliation remain pending

## Scope

This review covers bounded Restic JSON capture, additive reconciliation of
unrecorded Operator snapshot evidence, stale-success status disclosure, and one
supervised recovery run. It authorizes no deletion, retention execution,
credential change, source-scope change, or installed persistence.

## Files changed

- `lib/soul_core/bounded_command_runner.rb`: adds closed, bounded
  `complete_line_tail` capture and streaming JSON-line projection while
  preserving prefix capture as the default.
- `lib/soul_core/backup_administration_service.rb`: uses complete-line capture
  for backup NDJSON, reports successful unreceipted mutation as indeterminate,
  and adds additive digest-bound Operator evidence reconciliation.
- `lib/soul_core/backup_retention_ledger.rb`: exposes a content-free checkpoint
  for exact reconciliation planning.
- `lib/soul_core/nightly_drs_deployment.rb`: separates timer readiness from
  36-hour success freshness and operational health.
- `scripts/soul-backup-snapshot-reconcile`: bounded foreground credential-aware
  preview/execute entry point.
- `scripts/verify-bounded-command-runner.rb` and
  `scripts/verify-operator-drs-stream-reconciliation-a0.rb`: regression and
  reconciliation verification.
- `scripts/verify-nightly-drs-automation-a2-a3.rb`, `Makefile`, and
  `docs/soul/BACKUP_AND_RECOVERY.md`: status coverage and operator guidance.

## Commands and results

- Ruby syntax checks: passed.
- `ruby scripts/verify-bounded-command-runner.rb`: passed, 11 checks including
  NDJSON output larger than two MiB and raw-output-independent JSON projection.
- `ruby scripts/verify-operator-drs-stream-reconciliation-a0.rb`: passed, 10
  checks, including shared-lock and absent-checkpoint failure paths.
- `ruby scripts/verify-nightly-drs-automation-a2-a3.rb`: passed, including
  fresh and stale success-health cases.
- Full Backup Administration, Operator Backup, nightly DRS transaction and
  automation, storage/retention census, manifest reconciliation, and Crucible
  replication regression suite: passed.
- Live read-only streaming qualification against one affected snapshot:
  passed; 46,911 projected paths, 4,548,889 retained path bytes, no truncation,
  and 93.5 MiB transient-unit peak memory. No path content was emitted.

## Known weaknesses

- Reconciliation records local evidence only; a later ordinary DRS transaction
  must copy absent lineage to Crucible.
- Live reconciliation and the recovery DRS run have not yet been performed.
- The first live reconciliation attempt failed before mutation because the
  older 16 MiB raw path-inventory capture ended within a JSON record. The
  follow-up streams each record, retains only bounded path projections, and
  fails closed on invalid, oversized, or excessive records.
- Storage-heavy Unreal and cache exclusions remain a separate scope review.

## Lifecycle and memory

- Expected lifecycle states: `complete`, `failed`, `awaiting_input`, and
  `blocked_for_human_review`.
- No Soul conversational memory keys are added or used.
- Reconciliation receipts remain owner-private backup operational evidence.

## Risk classification

High operational importance, additive backup metadata mutation, and no backup
content deletion. Primary-agent independent validation and human merge review
remain required.

## Human review checklist

- [x] Complete-line capture preserves the default runner behavior.
- [x] Successful-but-unreceipted snapshots are never described as no mutation.
- [x] Reconciliation is exact, additive, bounded, and idempotent.
- [x] Existing timers, credentials, and repositories remain unchanged by the candidate.
- [ ] Local and Crucible lineage are verified after supervised recovery.
