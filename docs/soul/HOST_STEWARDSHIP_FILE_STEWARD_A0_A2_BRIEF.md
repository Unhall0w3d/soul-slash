# Host Stewardship and File Steward A0-A2 Brief

status: human-approved
approved_by: Operator
approved_on: 2026-08-14
risk: Class 2 read-only host composition plus Class 3 approval-gated reversible local file mutation

## Purpose

Deliver one coherent Administration candidate with:

1. **Host Stewardship A0** — a deterministic capability registry declaring
   evidence sources, dependencies, privacy, authority, lifecycle, and current
   availability;
2. **Host Presence A1** — one foreground read-only summary composed from the
   existing host, Core, persisted Wazuh, and backup-automation evidence; and
3. **File Steward A0-A2** — configured-root inventory, exact previewed
   rename/move/copy, owner-private quarantine, and exact restoration.

This work extends existing services. It does not introduce another model,
memory layer, indexer, security agent, backup engine, scheduler, watcher, or
background process.

## Host Stewardship contract

The capability registry must identify each reviewed capability using a stable
ID and return:

- maturity and availability;
- evidence source and freshness mode;
- privacy and mutation class;
- approval and lifecycle behavior;
- required and optional local dependencies; and
- an explicit unavailable reason where applicable.

Host Presence may collect current bounded host evidence and compose it with
current Core status, the latest persisted Wazuh snapshot, and the existing
backup-automation status. It must preserve source boundaries and timestamps;
it must not infer that stale, absent, or unavailable evidence is healthy.

Host Presence is read-only. Opening its Dashboard page may run one bounded
foreground refresh. No recurring polling follows.

## File Steward configuration

`SOUL_FILE_STEWARD_ROOTS` is the only mutation-root authority. It is distinct
from `SOUL_FILES_INSPECT_ROOTS`; read access never grants write access.

The value uses semicolon-separated `root_id=path` entries. The public default
is empty and therefore mutation-unavailable:

```dotenv
SOUL_FILE_STEWARD_ROOTS=
```

Deployment-specific absolute paths remain in the ignored local `.env`.
Conversation content and Dashboard fields cannot enroll or widen roots.

## File Steward A0 — inventory

The Operator may list configured root IDs and inspect one non-recursive
directory level below one configured root. Inventory:

- returns public root IDs and relative paths, never configured absolute roots;
- omits hidden, secret-shaped, inaccessible, symbolic-link, socket, device,
  and other unsupported entries;
- returns at most 200 entries after scanning at most 2,000; and
- performs no mutation or durable indexing.

## File Steward A1 — exact reversible operations

The Operator may preview and then execute one exact regular-file operation:

- `rename` within one directory;
- `move` between configured roots on the same filesystem; or
- `copy` between configured roots.

Every preview binds the action, public root IDs, normalized relative paths,
source device/inode/size/mtime fingerprint, destination absence, relevant
limits, and exact confirmation phrase into a SHA-256 digest. Execution must
revalidate the entire scope, refuse stale previews, and write an owner-private
receipt.

No operation may overwrite an existing destination. Directory operations,
recursive traversal, symbolic links, hidden or secret-shaped paths, hard-link
sources, device files, sockets, FIFOs, and cross-filesystem moves are blocked.
Copy is limited to 512 MiB and 30 seconds, writes to an exclusive temporary
file, verifies size and SHA-256, then atomically installs the destination.

## File Steward A2 — quarantine and restore

Quarantine moves one exact regular file into the fixed owner-private
`Soul/private/file_steward/quarantine/` store after a digest-bound preview and
confirmation. The original public root ID and relative path, source
fingerprint, quarantine identity, checksum, timestamp, and receipt are retained
in owner-private operation state.

Quarantine is limited to 4 GiB. SHA-256 verification is bounded to 60 seconds;
a verification failure rolls the move back to the original path.

Restore requires its own fresh preview, digest, and exact confirmation. It
restores only to the original configured root and relative path, and only when
that destination remains absent. Restore verifies the quarantined file's
checksum before mutation. Quarantine entries are never pruned or permanently
deleted by this slice.

## Shared boundaries

The implementation must:

- use lifecycle states `complete`, `failed`, `awaiting_input`, `canceled`, or
  `blocked_for_human_review`;
- keep all operations bounded and foreground;
- fail closed on invalid roots, traversal, symlinks, races, stale previews,
  collisions, permission errors, dependency failures, or changed evidence;
- retain no file contents in previews, receipts, logs, or model context;
- treat filenames and metadata as private local evidence;
- add no permanent-delete operation;
- add no Chat or Voice mutation invocation in this slice; and
- leave the existing Downloads cleanup workflow compatible and unchanged.

## Persistence prohibition

This slice adds no service, daemon, watcher, listener, scheduled task, timer,
cron job, background queue, unbounded poll, or continuation after returning
control to the Operator.

## Acceptance

- capability registry records agree with implemented operations and visible
  Dashboard boundaries;
- Host Presence distinguishes healthy, attention, and unavailable evidence
  without inventing state;
- read roots cannot be used as write roots unless separately configured;
- inventory and all mutation path protections pass deterministic tests;
- stale previews, changed sources, destination collisions, symlinks, hard
  links, cross-filesystem moves, oversized copies, and incorrect confirmations
  fail closed;
- rename/move/copy produce verified receipts;
- quarantine and restore round-trip an exact file without permanent deletion;
- Dashboard navigation survives refresh and clearly separates read-only Host
  Presence from approval-gated File Steward operations; and
- documentation, setup surface, Project Timeline, and human-review artifact
  agree before review.
