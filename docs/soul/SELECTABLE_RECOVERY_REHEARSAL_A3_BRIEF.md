# Selectable Recovery Rehearsal A3 Brief

Status: Implemented and human-accepted on 2026-08-09

## Objective

Prove that either encrypted repository can reconstruct one exact verified
snapshot in an Operator-selected isolated directory without writing into
Soul's live tree. A Crucible rehearsal must bind the selected local snapshot
to the remote snapshot carrying its preserved original lineage.

## Approved operation

The existing **Administration → Backup & Recovery** restore gate may add:

- a repository selector: local encrypted repository or Crucible encrypted
  second copy;
- an optional exact absolute recovery directory;
- full-snapshot recovery coverage evidence derived from the verified snapshot
  manifest; and
- a private restore receipt identifying repository source, source lineage,
  restored snapshot, target identity, content inventory, and coverage classes.

Blank recovery directory input preserves the accepted managed staging behavior.
An explicit directory performs a recovery rehearsal only when the restore is a
full snapshot. Selected-path restores remain ordinary isolated staging.

## Selected-directory boundary

The selected directory must:

- already exist and be an exact normalized absolute path;
- be a real directory whose path traverses no symlink;
- be owned by the current Operator and mode `0700`;
- be readable, writable, searchable, and empty;
- not be `/`, the home directory, the project tree, backup state, the local
  backup mount/repository, or an ancestor/descendant of those locations; and
- not be an ancestor or descendant of any configured backup source.

Its device, inode, owner, and mode are bound into the preview digest and
revalidated before restic starts. Directory contents are rechecked at execute
time. The operation does not create or chmod an arbitrary selected path.

## Crucible boundary

Crucible restore uses only the reviewed fixed SSH alias, owner, mode, SFTP
repository, and repository identity. The Dashboard continues to display local
snapshot identities. Preview resolves that local ID to exactly one Crucible
snapshot whose `original` lineage matches it, then binds both identities into
the approval digest. Missing lineage blocks the operation.

## Verification and lifecycle

Restic runs once with `restore --verify` under the existing 60-minute bound.
Soul hashes the staged inventory and, for full rehearsals, verifies that every
documented source root materialized beneath the selected directory. Evidence
classifies private state, conversation state, creative archives, Knowledge
Vault, and service configuration coverage without granting promotion authority.

Successful staging ends `blocked_for_human_review`. There is no automatic retry,
live-tree promotion, service stop/start, session restoration, deletion, pruning,
scheduler, watcher, daemon, or background continuation.

## Acceptance

- Managed private staging remains backward compatible.
- Unsafe, nonempty, changed, symlinked, or overlapping targets fail closed.
- Local full recovery binds the selected target and verifies every manifest root.
- Crucible full recovery proves original-lineage selection and reads through the
  fixed SFTP transport.
- Password bytes appear only in bounded restic child environments.
- The receipt records exact source/target evidence and no credential.
- Human live qualification restores a reviewed snapshot into a selected empty
  directory and inspects representative private, conversational, creative,
  knowledge, and service configuration evidence.
