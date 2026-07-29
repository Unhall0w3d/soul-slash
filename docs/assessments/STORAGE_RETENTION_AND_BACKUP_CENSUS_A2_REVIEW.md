# Storage, Retention, and Backup Census A2 Review

Status: candidate-complete; human review required

## What was implemented

Storage & Retention now inventories active Soul artifact classes rather than
only measuring a few large directories. Each class declares its owner, generic
path family, retention class, deletion boundary, backup expectation, current
size, and current coverage state.

The read-only census compares:

- the owner-managed Restic source allow-list;
- the owner-managed exclusion list;
- the latest retained backup path manifest, when present;
- independent local metadata such as the presence of a Knowledge Vault Git
  repository.

It does not inspect chats, notes, prompts, lyrics, credentials, media, or other
private content. It accepts no password and cannot create, prune, restore,
replicate, move, or delete anything.

The latest workstation evidence reports:

- 45 registered artifact classes;
- 32 classes requiring encrypted backup;
- 29 required classes verified in the latest retained snapshot;
- the local Knowledge Vault, chats, core private state, Music/Visual projects,
  and finished exports verified;
- three newer durable continuity paths not yet present in the existing owner
  source manifest;
- four disposable/cache classes lacking explicit exclusions in the existing
  owner exclusion manifest.

Private Git for the local Knowledge Vault is recorded as supplementary history,
not as a substitute for Restic coverage.

Portable backup setup now proposes the newer durable continuity paths and
explicit disposable/cache exclusions. Existing owner manifests are never
silently replaced.

The repository hygiene script now has a genuine non-mutating `--check` mode.
Its historical no-argument behavior remains the explicit apply-compatible
path, while `--apply` makes mutation intent unambiguous.

## Files changed

- `lib/soul_core/artifact_retention_census.rb`
- `lib/soul_core/storage_retention_assessor.rb`
- `scripts/soul-backup-config`
- `scripts/repo-public-hygiene-cleanup.sh`
- `scripts/verify-storage-retention-backup-census-a2.rb`
- `scripts/verify-storage-retention-a1.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `Makefile`
- `config/project_tracker_seed.json`
- `docs/soul/STORAGE_RETENTION_AND_BACKUP_CENSUS_A2_BRIEF.md`
- `docs/soul/BACKUP_AND_RECOVERY.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- this review artifact

## Commands run

```text
ruby scripts/verify-storage-retention-backup-census-a2.rb
ruby scripts/verify-storage-retention-a1.rb
ruby -c lib/soul_core/artifact_retention_census.rb
ruby -c lib/soul_core/storage_retention_assessor.rb
ruby -c scripts/soul-backup-config
ruby -c scripts/verify-storage-retention-backup-census-a2.rb
node --check assets/dashboard/dashboard.js
bash -n scripts/repo-public-hygiene-cleanup.sh
scripts/repo-public-hygiene-cleanup.sh --check
```

Additional regression commands are listed below and must pass before the
candidate is published.

## Deterministic results

- A2 census verifier: passed
- existing Storage & Retention A1 verifier: passed
- syntax checks: passed
- repository hygiene check: clean and non-mutating
- Backup Administration, Knowledge Vault, Dashboard, and application API
  regressions: passed

No local LLM evaluation is required. This slice validates filesystem metadata,
contracts, and deterministic coverage states rather than conversational
behavior.

## Known weaknesses and deferred work

- The current owner manifests are intentionally not rewritten by this change.
  The three durable source gaps and four exclusion gaps require a separate
  reviewed reconciliation.
- Latest-snapshot verification uses the retained path manifest. It does not
  unlock or query Restic and therefore depends on the existing verified
  manifest lifecycle.
- The census does not infer that a Git remote is private and does not expose a
  remote URL.
- Some legacy runtimes remain manual-review material because their removal
  requires separate compatibility and rollback decisions.
- Cleanup execution, automatic expiry, schedules, watchers, background
  reconciliation, and snapshot pruning remain unavailable.
- A future cleanup executor must preserve finished exports and respect every
  accepted project/candidate deletion boundary.

## Memory keys

No shared Soul memory keys were added or changed.

## Lifecycle states touched

The assessment is a bounded foreground read that ends `complete` with evidence
or `failed` with a visible error. It creates no resumable or silently running
task.

## Risk classification

Low. The implemented operation is metadata-only and non-mutating. Portable
manifest defaults affect only a future exact-gated setup action and never
replace existing machine-owned manifests.

## Human review checklist

- [ ] Open **Self Assessment → Storage & Retention**.
- [ ] Confirm artifact classes show owner, footprint, retention class, and
  backup state.
- [ ] Confirm the Knowledge Vault is shown as latest-snapshot verified and
  local Git is treated only as supplementary.
- [ ] Confirm chats, private state, Music/Visual projects, and finished exports
  are latest-snapshot verified.
- [ ] Confirm the three durable source gaps and four exclusion gaps are visible
  without exposing private content or credentials.
- [ ] Confirm no cleanup action is offered.
- [ ] Review the proposed owner-manifest reconciliation before changing local
  manifests or creating a new snapshot.
- [ ] Approve or reject the candidate independently from deterministic tests.
