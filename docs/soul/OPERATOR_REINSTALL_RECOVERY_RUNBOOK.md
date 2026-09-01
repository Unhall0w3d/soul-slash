# Operator Reinstall Recovery Runbook

This runbook supplements encrypted Soul and Operator DRS. It covers large local
runtime state that is intentionally absent from automatic backup policy.

## Stop boundary

Do not start the reinstall until all of the following are true:

- the WinBoat container is stopped and its disk image has no open writer;
- Unreal Editor and Trellis runtime processes are stopped;
- Downloads and Recovered have received their final human disposition;
- tracked repositories are clean or their intentional local work is recorded;
- fresh Soul and Operator DRS captures and exact Crucible lineages verify; and
- a representative staged restore verifies without touching live state.

## Cold-copy inventory

Use a timestamped directory on the reviewed external migration disk. Store
POSIX metadata inside uncompressed tar archives because the carrier filesystem
may not preserve Linux ownership, modes, ACLs, extended attributes, or sparse
files when copied directly.

```text
WinBoat
  ~/winboat/data.img                    sparse container disk
  ~/.winboat                            deployment state
  ~/.config/winboat                     selected desktop state

Unreal Engine
  ~/.local/share/unreal-engine          installed engine bulk data
  ~/Projects/space-sim                  Project Wraith working tree

Trellis
  ~/.local/share/project-wraith/trellis local runtimes, models, downloads, and source variants
```

WinBoat's sparse image must be archived with sparse-file support; a plain copy
to a filesystem without sparse-file support can expand it to its full logical
size. The Project Wraith working tree is selected by the Operator profile but
must also receive a cold archive that retains modified and untracked files.
A temporary private Git migration remote and an exact recovery clone were
verified on 2026-09-01. Before reinstall, refresh the migration snapshot after
active development lands and confirm the remote ref still matches the reviewed
worktree. The engine and Trellis runtime archives are convenience recovery
copies, not source control.

## Copy and verification contract

For each stopped source group:

1. Re-resolve and record the target mount, filesystem, free space, and source
   directory size immediately before copying.
2. Create a tar archive with sparse-file, ACL, extended-attribute, and numeric
   ownership preservation. Do not overwrite an existing archive.
3. Record the archive byte size and SHA-256 digest in a manifest beside it.
4. List the archive and verify the required top-level paths.
5. After all archives finish, unmount and reconnect the carrier, recompute the
   SHA-256 manifest, and open-list each archive again.
6. Keep the source trees unchanged until the replacement installation has
   restored and exercised the corresponding application.

The cold-copy operation remains a separately supervised foreground action. No
automatic cleanup, overwrite, retention, or live restore is authorized.

## Current storage decision evidence

A bounded 512 MiB synchronous-write comparison on 2026-09-01 measured:

```text
external 2 TB WD USB hard disk: 97.7 MiB/s
internal 1 TB Seagate SATA hard disk: 162.7 MiB/s
```

The external device reports as a 5,400 RPM rotating disk, not an SSD. It remains
the primary migration carrier because it is removable and has sufficient
capacity. The faster Seagate may hold an optional second cold copy only after a
clean SMART review. The separate WD RE4 failed its extended SMART test and must
not hold unique recovery data.

Project Wraith is suitable for its intended private Git remote: its reachable
history is approximately 964 MiB, no reachable blob exceeds the 100 MiB GitHub
limit, current tracked files total approximately 2.8 MiB, and current
non-ignored untracked files total approximately 4.0 MiB. Unreal build output
and Trellis artifacts account for most of the 4.8 GiB working tree and are
already ignored. The private remote does not remove the need for a cold archive
of modified and untracked work.

## Restore order

1. Install and update the replacement operating system.
2. Clone the required public and private repositories and verify their remotes.
3. Stage and review the Operator restore before any promotion.
4. Restore approved dotfiles, credentials, user data, and application state.
5. Reinstall WinBoat, Unreal, and Trellis prerequisites before extracting their
   cold-copy archives into owner-reviewed staging paths.
6. Validate each application from staging, then promote deliberately.
7. Re-enroll or rotate host-bound credentials and verify outbound SSH.
8. Run a fresh post-migration Soul and Operator DRS transaction.
