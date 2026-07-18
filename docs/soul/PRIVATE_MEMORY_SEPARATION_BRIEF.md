# Private Memory Separation brief

Status: human-approved and live-verified (2026-07-18)

## Objective

Separate durable owner-specific memory from files shipped by the public
repository without losing data, changing memory semantics, or silently cutting
over an existing installation.

## Included

- An ignored `Soul/private/memory/` destination for owner-specific memory.
- Compatibility resolution that keeps an existing installation on its legacy
  files until a verified migration marker exists.
- Fresh-clone behavior that writes durable memory directly to the private root.
- A tracked public-seed marker that distinguishes neutral defaults from an
  older installation's mutable legacy files.
- A bounded migration preview covering these allowlisted legacy files when
  present: aliases, user preferences, projects, lessons, approved lessons,
  approved rules, the conversation-memory ledger, and JSON snapshot exports.
- Exact SHA-256 binding, exact confirmation, atomic private copies, owner-only
  file modes, post-copy verification, and a cutover marker written last.
- Shared writer updates for conversation memory, reflection promotion, snapshot
  export, and project-aware Downloads inspection.
- Storage assessment visibility for both private memory and retained legacy
  rollback sources.

## Excluded

- Deleting, moving, truncating, or rewriting a legacy source.
- Sanitizing the tracked legacy files before the private copies are approved and
  verified on the live installation.
- Rewriting Git history. Any owner-specific content already published in Git
  history requires a separately reviewed history-remediation decision.
- Memory promotion, forgetting, semantic changes, automatic migration, service
  restart, background process, watcher, scheduler, or network operation.

## Safety contract

- Preview reads file metadata and hashes but does not emit file content.
- Only seven exact root filenames and at most 512 direct JSON exports are in
  scope; each file is capped at 64 MiB and total input at 256 MiB.
- Source files, destination files, and every existing destination ancestor must
  be regular non-symlink entries of the expected type.
- Execution requires `COPY_PRIVATE_MEMORY_STATE` and the current preview digest.
- Source changes or destination conflicts invalidate the preview.
- Execution copies and verifies every file before writing the cutover marker.
- Failure removes only new incomplete destination copies; sources remain intact.
- The operation terminates as `complete`, `failed`, `awaiting_input`, or
  `blocked_for_human_review` and starts no continuing work.

## Gates

1. Review implementation, deterministic tests, and live preview.
2. Human explicitly authorizes the digest-bound live copy.
3. Verify private copies and runtime cutover.
4. In a separate reviewed patch, replace tracked owner state with neutral public
   seed templates. Do not erase the retained private copy.
