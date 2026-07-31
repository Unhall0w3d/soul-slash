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

## Live qualification

Qualification completed on 2026-07-31:

- The reviewed Atelier policy resolved 117 owner-selected source roots. Raw
  model weights remain excluded in favor of pinned revision and SHA-256
  recovery evidence.
- A supervised Operator DRS transaction verified snapshot
  `11d0b549…e294c` locally and reconciled exact lineage to Crucible.
- A systemd-triggered qualification run completed in 34.7 seconds with local
  snapshot `b081a699…c7839d` and exact Crucible lineage verification. The
  permanent `soul-operator-nightly-drs.timer` is enabled for 2:00 AM local
  time with no retry, retention, or deletion authority.
- Crucible's dedicated XFS backup disk was expanded online from 100 GiB to
  200 GiB before permanent qualification.
- Restore receipt `restore_20260731T212748Z_369e5596cb475fa0` verifies an
  isolated four-file recovery from `b081a699…c7839d`: SSH configuration, a
  maintenance private key, `.zshrc`, and personal document data. Restored
  SHA-256 hashes and modes match live state; the key derives the same public
  identity and the restored SSH configuration resolves `forge` identically.
  Unprivileged staging ownership is explicitly normalized to the current
  operator, and live state remains unchanged.

Operator Backup A0 is qualified recovery coverage. Staged recovery promotion,
retention execution, and deletion remain separate human-reviewed procedures.
