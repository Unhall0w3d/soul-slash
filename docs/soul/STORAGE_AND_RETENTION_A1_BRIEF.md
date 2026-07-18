# Storage and Retention A1 brief

Status: human-approved implementation scope (2026-07-18)

## Objective

Add a bounded, read-only Storage scope to Self Assessment. It must inventory
Soul-owned local storage, distinguish protected data from reviewable cleanup
candidates, expose current dashboard memory evidence, and prepare exact cleanup
previews without deleting or moving anything.

## Included

- Point-in-time size and retention classification for private music projects,
  production and legacy music runtimes, retained Vulkan pilots, transcription,
  finished exports, project logs, shared memory, and known Soul review residue
  in the system temporary directory.
- Current and peak memory reported by the existing dashboard user service.
- Exact read-only cleanup previews for:
  - allowlisted Soul review residue older than 24 hours;
  - regular project log files older than 30 days;
  - failed music candidate quarantine directories older than 24 hours when no
    music lease is active.
- A Self Assessment dashboard surface that runs only when requested.
- Deterministic tests and a human review artifact.

## Excluded

- File deletion, Trash movement, package cleanup, log rotation, model removal,
  automatic expiry, startup cleanup, scheduled cleanup, watchers, polling, or a
  background measurement process.
- Cleanup of accepted pilot audio, finished exports, private music projects,
  shared memory, production model files, or unknown temporary paths.
- The separate migration from tracked memory defaults to ignored private memory.

## Safety contract

- Inventory reads metadata only and never reads private content.
- Symlinks are reported as blocked and never followed.
- Candidate discovery is prefix/path allowlisted, entry-capped, age-bounded,
  owner-bounded where applicable, and protected by the Self Assessment timeout.
- Previews bind exact paths, sizes, timestamps, category, and a SHA-256 digest.
- A1 registers no cleanup execute operation. Preview output explicitly states
  that execution is unavailable pending a later human-approved slice.
- The operation terminates as `complete`, `failed`, `awaiting_input`, or
  `blocked_for_human_review`; it never remains active after returning.

## Acceptance

- Opening Self Assessment still performs only the existing lightweight snapshot.
- Selecting Storage performs one foreground inspection with no writes.
- Production/private/protected categories cannot appear in cleanup previews.
- Unknown `/tmp/soul-*` paths are visible as protected unknown residue, not
  silently classified as disposable.
- Dashboard memory evidence is clearly point-in-time and does not poll.
- Existing Self Assessment and application-contract regressions pass.
