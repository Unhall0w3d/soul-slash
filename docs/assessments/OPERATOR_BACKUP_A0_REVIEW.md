# Operator Backup A0 Review

## Candidate

Operator continuity profile: selective workstation data, dotfiles,
application state, private recovery credentials, and host-rebuild evidence.

## Review findings

- Raw `~/ai_models` weights are reproducible and consume approximately 21 GiB,
  so A0 excludes them and tracks exact recovery metadata in
  `config/operator_recovery_assets.json`.
- Personal media remains intentionally in scope.
- Projects remain in scope while generated build outputs and Soul's separately
  protected project tree are excluded.
- The profile defaults to the existing encrypted repositories but uses the
  `operator-state` tag and private `Soul/private/operator_backup` state.
- Soul and Operator mutations share the existing non-blocking operation lock.
- Operator scheduling is separately qualified at 2:00 AM local time with its
  own unit names, host-encrypted credential, state, confirmations, and receipts.
  Soul's accepted 3:00 AM units remain byte-compatible and independent.
- Outbound SSH client recovery is covered by the encrypted `~/.ssh` source,
  including config, known hosts, and key material. GnuPG, keyrings, GitHub CLI
  configuration, and encrypted credential stores are also selected.

## Outstanding live qualification

1. Review `make operator-backup-config-plan` against the actual workstation.
2. Configure the manifests with the exact reviewed digest.
3. Enroll the separate Operator credential and qualify one timed run.
4. Install and inspect the fixed 2:00 AM timer.
5. Reconcile that exact lineage to Crucible and verify it.
6. Stage a representative SSH configuration/key set, dotfile, and personal-data restore, inspect it, and
   remove staging only through the normal reviewed procedure.

Until those steps pass, this is a candidate implementation, not qualified
recovery coverage.
