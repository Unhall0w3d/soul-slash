# Operator Migration Readiness A1 Review

## Candidate

Tracked Soul and Operator backup-policy extension for a possible workstation
reinstall.

Risk class: protected backup policy; independently reviewed live mutation and
fresh recovery qualification are still required.

Candidate status: `candidate_complete`

## Implementation summary

- Added the approved Codex, Opera GX, creator-tool, selected game, Lutris,
  Ollama metadata, Applications, and Cisco paths to the Operator allow-list.
- Added explicit Opera GX cache, crash, shader, service-worker-cache, and live
  singleton exclusions.
- Added only three retained run-output roots from `~/.local/share/soul` to the
  Soul policy; the approximately 77 GiB parent runtime/model tree remains out
  of scope.
- Retained active Codex sessions, raw AI/model blobs, Downloads, Recovered,
  WinBoat disks, Unreal bulk data, and Trellis bulk data outside this automatic
  policy slice.

## Files changed

```text
- lib/soul_core/backup_manifest_policy.rb
- lib/soul_core/operator_backup_manifest_policy.rb
- scripts/verify-backup-manifest-reconciliation-a0.rb
- scripts/verify-operator-backup-a0.rb
- docs/soul/BACKUP_AND_RECOVERY.md
- docs/soul/OPERATOR_BACKUP_A0_BRIEF.md
- docs/soul/OPERATOR_MIGRATION_READINESS_A1_BRIEF.md
- docs/soul/OPERATOR_REINSTALL_RECOVERY_RUNBOOK.md
- docs/assessments/OPERATOR_MIGRATION_READINESS_A1_REVIEW.md
```

## Commands and deterministic results

```text
ruby -c lib/soul_core/operator_backup_manifest_policy.rb
ruby -c lib/soul_core/backup_manifest_policy.rb
ruby -c scripts/verify-operator-backup-a0.rb
ruby -c scripts/verify-backup-manifest-reconciliation-a0.rb
Result: pass

ruby scripts/verify-operator-backup-a0.rb
Result: pass

ruby scripts/verify-backup-manifest-reconciliation-a0.rb
Result: pass

ruby scripts/verify-backup-administration-a2.rb
ruby scripts/verify-storage-retention-backup-census-a2.rb
Result: pass

git diff --check -- <migration-readiness paths>
Result: pass

read-only Operator reconciliation preview
Result: 26 source additions, 15 exclusion additions, zero removals

read-only Soul reconciliation preview
Result: 10 source additions, zero exclusions, zero removals; three additions
are this slice's retained local run trees and seven are pre-existing Soul user
service files not yet present in the live manifest

bounded synchronous-write comparison with automatic test-file cleanup
Result: external WD USB disk 97.7 MiB/s; Seagate SATA disk 162.7 MiB/s

read-only cold-copy inventory
Result: approximately 132 GiB physically allocated across current WinBoat,
Unreal Engine, Trellis, and Project Wraith paths; WinBoat's 80 GiB logical disk
uses approximately 44 GiB physically and had no open writer after shutdown

read-only Project Wraith Git suitability review
Result: approximately 964 MiB reachable repository history; largest blob 72.0
MiB; no blob at or above 100 MiB; approximately 2.8 MiB currently tracked and
4.0 MiB non-ignored untracked; private Git is suitable while ignored bulk still
requires cold-copy or reproducible installation treatment

Project Wraith private migration publication and recovery exercise
Result: private repository created; main, both development branches, isolated
migration branch, and annotated migration tag pushed; remote branch and peeled
tag resolve to the exact local snapshot; a clean filtered clone recovered all
365 selected paths and initialized the recorded public tooling submodule; the
active development branch and index remained unchanged
```

Local LLM evals: not applicable; this slice changes deterministic filesystem
policy and no model-mediated behavior.

## Memory and lifecycle behavior

Memory keys read or written: none.

Lifecycle states touched: read-only policy planning and reconciliation preview
completed. No live manifest, backup, restore, retention, or deletion lifecycle
was entered.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Known weaknesses and remaining work

- The live manifests still require exact human-reviewed reconciliation.
- A fresh encrypted Operator and Soul capture plus exact Crucible lineage
  verification is required before reinstall readiness is established.
- WinBoat, Unreal, and Trellis bulk state still require explicit cold-copy
  inventory, copy, hash/size verification, and restore notes.
- The external migration carrier is a 5,400 RPM USB hard disk rather than an
  SSD. It is slower than the Seagate but has the required capacity and
  removability. The Seagate still requires a clean SMART review.
- Downloads and Recovered remain pending human review.
- An older smaller WinBoat image exists inside Recovered and must not be
  mistaken for the current stopped 80 GiB logical image.
- Project Wraith now has a verified private migration remote and snapshot, but
  active development remains modified and untracked on its working branch. A
  refreshed exact snapshot, cold working-tree copy, and Operator snapshot all
  remain pre-reinstall gates.
- Root-only network configuration and host-bound credentials require their
  existing independent recovery procedures.

## Human review checklist

```text
[ ] Exact source and exclusion additions are accepted
[ ] No unapproved whole runtime, model, browser cache, or bulk project tree entered scope
[ ] Manual migration ledger is complete
[ ] Cold copies are size/hash verified on dedicated media
[ ] Live manifest reconciliation is separately approved
[ ] Fresh local and Crucible snapshots verify
[ ] Representative staged restore verifies before reinstall
```

## Human review outcome

```text
Outcome: pending
Reviewer: Operator
Date:
Decision summary:
Required changes:
```
