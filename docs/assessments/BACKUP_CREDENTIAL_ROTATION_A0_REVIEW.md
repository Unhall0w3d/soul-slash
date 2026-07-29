# Backup Credential Rotation A0 Review

Status: candidate implementation; live rotation deferred until the Operator returns

## Implemented

One local interactive command preflights both configured restic repositories,
changes each repository's sole access key with `restic key passwd`, verifies
repository identity and snapshot preservation, rejects the prior credential,
and rolls back completed repositories if a later step fails. It shares Backup
Administration's nonblocking operation lock so capture, retention, restore,
replication, and credential rotation cannot overlap.

Secrets travel only through inherited anonymous file descriptors exposed to
the bounded child as `/proc/self/fd/3` and `/proc/self/fd/4`. The wrapper
requires a real terminal, disables echo, and wipes its in-memory string copies
on exit.

## Files changed

- `lib/soul_core/secret_file_command_runner.rb`
- `lib/soul_core/backup_credential_rotation_service.rb`
- `scripts/soul-backup-credential-rotation`
- `scripts/verify-backup-credential-rotation-a0.rb`
- `Makefile`
- backup guide, brief, review artifact, and Project Timeline seed

## Commands and deterministic results

```text
ruby -c lib/soul_core/secret_file_command_runner.rb
ruby -c lib/soul_core/backup_credential_rotation_service.rb
ruby -c scripts/soul-backup-credential-rotation
ruby -c scripts/verify-backup-credential-rotation-a0.rb
make verify-backup-credential-rotation
make verify-backup-administration
make verify-crucible-backup-replication
make verify-project-timeline
git diff --check
```

## Local LLM evals

Not applicable. Credential transport, exact repository evidence, and mutation
boundaries are deterministic contracts.

## Known weaknesses

- A repository with more than one access key is deliberately blocked rather
  than automatically reconciled.
- Process memory necessarily contains the password while the foreground
  operation runs; the wrapper wipes its owned string copies afterward.
- A machine crash between repositories can leave one repository on the new
  password and one on the old password. Both human-known credentials remain
  sufficient for bounded recovery.

## Memory, lifecycle, and risk

No memory keys or durable secret state are used. The operation terminates as
`complete`, `awaiting_input`, or `failed`. Risk is Class 4 because repository
access credentials are replaced, although backup content is not mutated.

## Human review

- [x] Fixture rotation passes with different local and replica repository IDs.
- [x] No password appears in argv, environment, files, receipts, logs, or Git.
- [ ] Live preflight confirms one key and unchanged snapshot inventory on both
  repositories.
- [ ] Live rotation accepts the new password and rejects the old password on
  both repositories.
- [ ] Project Timeline records completion without private key or snapshot IDs.
