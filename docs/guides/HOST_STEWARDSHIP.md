# Host Stewardship and File Steward

Host Stewardship is Soul's owner-facing surface for understanding the local
host before deciding whether any action is appropriate. Open it from
**Administration → Host Stewardship**.

This A0–A2 candidate contains three related but separate boundaries:

- the **Capability Registry** declares what exists, its maturity, evidence,
  privacy, mutation class, dependencies, and approval requirement;
- **Host Presence** composes a bounded foreground snapshot of current host and
  Core evidence with source-attributed persisted Wazuh and backup-automation
  status; and
- **File Steward** inventories explicitly configured roots and stages exact,
  reversible regular-file operations.

## Configure File Steward roots

Read-only `SOUL_FILES_INSPECT_ROOTS` do not grant mutation authority. File
Steward has a separate, empty-by-default allowlist:

```dotenv
SOUL_FILE_STEWARD_ROOTS=downloads=/home/operator/Downloads;documents=/home/operator/Documents
```

Root IDs are public interface labels. Absolute paths remain local
configuration and are not returned by the application API. Configure only the
smallest directories in which Soul should be allowed to stage reviewed file
work.

## Host Presence

Opening the page performs one foreground read. **Read current presence**
performs another. The page does not start a watcher, daemon, timer, or polling
loop. Every signal retains its source timestamp, and unavailable sources remain
unavailable rather than being inferred.

Host Presence currently summarizes memory use, CPU load, highest mounted
filesystem use, failed user units, active Core evidence, persisted Wazuh
posture, and nightly backup-automation readiness. It is an interpretation
surface, not a second system monitor.

## File inventory

Choose one configured root and one relative directory. Inventory returns at
most 200 visible regular files or directories after scanning at most 2,000
entries. Clicking a directory performs another bounded one-level read;
clicking a file selects it as the exact operation source.

Hidden and secret-shaped paths, symlinks, devices, sockets, FIFOs, and other
unsupported entries are omitted. There is no recursive crawl.

## Rename, move, and copy

Choose one action, exact source, and exact destination, then select **Preview
exact operation**. The preview binds normalized public-root paths, source
fingerprint, destination absence, action, limits, and the exact confirmation
into a SHA-256 digest.

The final button is the authority gesture. Execution rebuilds and revalidates
the plan. It stops safely when the source changed, the destination appeared,
or a boundary no longer holds. Rename stays within one directory. Move stays
on one filesystem. Copy is limited to 512 MiB and 30 seconds, uses an exclusive
temporary file, and verifies exact bytes and SHA-256 before publication.

## Quarantine and restore

Quarantine is reversible removal, not deletion. It moves one exact file on the
same filesystem into `Soul/private/file_steward/quarantine/`, verifies its
checksum, and records owner-private lineage and a receipt. The current limit is
4 GiB with a 60-second checksum bound.

Restore has its own fresh preview and confirmation. It restores only to the
recorded configured root and relative path, only if that destination remains
absent, and only after the quarantined checksum still matches. Completed
entries remain in the ledger as closed evidence.

Permanent deletion is intentionally unavailable. File Steward also cannot
mutate directories, recurse through trees, overwrite destinations, follow
symlinks, touch hard-linked files, or operate on hidden and secret-shaped
paths.

## Verification

```bash
make verify-host-stewardship-file-steward
```

This proves the public root boundary, bounded inventory, stale-preview and
overwrite refusal, byte-verified copy, reversible quarantine/restore, absence
of permanent-delete operations, capability declarations, foreground-only Host
Presence, and Dashboard integration. It does not replace Operator review.
