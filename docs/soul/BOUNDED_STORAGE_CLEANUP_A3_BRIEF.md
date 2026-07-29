# Bounded Storage Cleanup A3 Brief

Status: human-approved for implementation on 2026-07-29

## Outcome

Turn the accepted Storage & Retention candidate preview into one exact,
foreground, human-authorized cleanup gate for three already classified
disposable or age-reviewable categories:

- known Soul review residue in the system temporary directory older than
  24 hours;
- regular project log files older than 30 days;
- failed partial Music candidate directories older than 24 hours when no Music
  lease is active.

No other artifact class becomes executable in this slice.

## Included

- Metadata-only recursive identity records for every candidate.
- Exact preview binding category, path, type, owner, age, size, tree identity,
  candidate count, and total bytes.
- One confirmation phrase supplied by the reviewed Dashboard button.
- Execute-time rediscovery and exact digest comparison.
- Non-waiting in-process operation exclusion.
- Same-parent staging before deletion, with inode verification and rollback of
  still-staged entries on failure.
- Bounded recursive removal of exact staged candidates only.
- Terminal application lifecycle evidence containing the exact removed scope,
  byte count, mutation class, and any partial-failure restoration result.
- One owner-only receipt under the existing age-reviewable project-log class;
  it stores only path/identity digests, counts, bytes, and lifecycle evidence.
- Dashboard completion feedback and a refreshed point-in-time census.
- Deterministic tests, documentation, and a human review artifact.

## Fixed eligibility

### Temporary review artifacts

- Direct child of the configured temporary root.
- Name begins with an existing approved `TEMP_PREFIXES` value.
- Owned by the current user.
- Regular file or directory only.
- Candidate and every descendant are at least 24 hours old.
- No symlink, device, socket, FIFO, or other special entry exists anywhere in
  the candidate tree.

### Expired project logs

- Regular file beneath `Soul/logs`.
- Owned by the current user.
- At least 30 full days old.
- No directory, symlink, or special entry is eligible.

### Failed Music quarantine

- Exact directory shape:
  `Soul/music/projects/*/generations/.candidate_*.partial`.
- Candidate and every descendant are owned by the current user and at least
  24 hours old.
- No Music resource lease is active at preview or execute time.
- No symlink or special entry exists anywhere in the candidate tree.
- Published candidates, project metadata, reviews, audio, finished exports,
  and non-partial directories are never selected.

## Safety boundaries

- Protected, lifecycle-owned, capacity-bounded, reproducible, and
  manual-review classes remain non-executable.
- Chats, memory, credentials, Knowledge Vault content, projects, accepted
  candidates, finished exports, backup evidence, and maintenance evidence
  cannot match any cleanup category.
- Discovery is bounded. An oversized directory or candidate set blocks rather
  than silently truncating an executable scope.
- Preview and execute never read file content.
- Every tree must be regular, owner-local, and symlink-free.
- Execute repeats discovery and requires the exact preview digest. Path,
  metadata, tree, age, ownership, lease, or category drift blocks before
  staging.
- Same-parent staging names are unique and must not pre-exist.
- After rename, device and inode identity must match the reviewed candidate.
- A failure restores every candidate that remains staged and reports any
  already removed candidates explicitly through the shared application
  receipt.
- Empty scope, wrong confirmation, stale digest, concurrent execution, unsafe
  ancestry, or active Music work changes nothing.
- No shell `rm`, Trash traversal, arbitrary path input, glob supplied by the
  client, elevated privilege, backup mutation, Restic operation, retry loop,
  timer, scheduler, watcher, daemon, or background continuation is added.

## Lifecycle

- `complete`: exact preview produced, no candidates found, or all exact staged
  candidates removed and verified absent.
- `awaiting_input`: category or confirmation is missing/invalid.
- `blocked_for_human_review`: scope drift, unsafe entry, candidate bound,
  active Music work, stale digest, or concurrent execution is detected.
- `failed`: staging/removal fails; remaining staged entries are restored and
  partial effects are disclosed.

No operation remains active after returning.

## Deterministic acceptance

- Preview exposes execution only for the three approved categories.
- Known old temporary residue is eligible; unknown/recent/symlinked/special or
  foreign-owned residue is not.
- Only old regular log files are eligible.
- Only old failed `.candidate_*.partial` trees are eligible and an active Music
  lease blocks them.
- Wrong confirmation, stale digest, candidate drift, symlink insertion,
  excessive scope, and concurrent execution remove nothing.
- Exact execution removes only the reviewed entries and leaves adjacent
  protected/recent/unknown entries byte-identical.
- Same-parent staging identity and rollback behavior are deterministic.
- A second preview is empty and terminal.
- Dashboard requires preview before the destructive button is available.
- Existing Storage, census, backup, Music, Self Assessment, and application
  regressions pass.

## Human review boundary

Passing tests makes this candidate-complete only. The Operator separately
approves merge and may then inspect each category through the Dashboard before
authorizing its exact current scope. No cleanup runs automatically.
