# Backup Credential Rotation A0 Brief

## Objective

Provide one bounded, local, interactive procedure that changes the access
password on the accepted local recovery repository and the independently
encrypted Crucible repository without exposing either credential to Chat, the
Dashboard, process arguments, receipts, logs, or Git.

## Approved scope

- Read the two exact repository locations from the existing private `.env`.
- Require an interactive terminal and exact `ROTATE_BACKUP_CREDENTIALS`
  confirmation.
- Read the current password and one confirmed replacement with terminal echo
  disabled.
- Pass secrets to restic through inherited anonymous file descriptors.
- Share the existing nonblocking Backup Administration operation lock.
- Require exactly one access key per repository before mutation.
- Preserve repository identity and the exact tagged snapshot inventory.
- Prove the replacement password opens both repositories.
- Prove the previous password opens neither repository.
- Attempt to restore already-changed repositories if a later repository fails.
- Terminate as `complete`, `awaiting_input`, or `failed`.

## Excluded

- Dashboard password entry or browser automation.
- Password persistence, keyrings, environment variables, files, logs, or
  receipts.
- Scheduled, detached, retried, or unattended execution.
- Repository initialization, snapshot mutation, retention, restore, or remote
  deletion.
- Multiple-key reconciliation; that state fails closed for human review.
