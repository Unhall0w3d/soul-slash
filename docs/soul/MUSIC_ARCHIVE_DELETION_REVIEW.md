# Music archive deletion candidate review

## Candidate status

`candidate_complete` — awaiting Operator review.

## Implementation summary

- Added permanent deletion for one selected Music Studio composition using a
  fresh tree inventory, digest, and `DELETE_MUSIC_PROJECT` confirmation.
- Added permanent deletion for one selected reference track profile using a
  fresh record/dependency digest and `DELETE_MUSIC_REFERENCE` confirmation.
- Project deletion preserves finished exports outside the project archive.
- Reference deletion blocks when a Fusion depends on the profile and removes
  empty derived artist/album groupings naturally.

## Files changed

- `lib/soul_core/music_project_deletion_service.rb`
- `lib/soul_core/music_reference_library_service.rb`
- `lib/soul_core/music_reference_library_store.rb`
- `lib/soul_core/music_resource_coordinator.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `scripts/verify-music-project-deletion.rb`
- `scripts/verify-music-reference-library-a5.rb`
- `docs/soul/MUSIC_PROJECT_ARCHIVE_DELETION_BRIEF.md`

## Commands and deterministic results

```text
ruby scripts/verify-music-project-deletion.rb          PASS
ruby scripts/verify-music-reference-library-a5.rb     PASS
node --check assets/dashboard/dashboard.js            PASS
git diff --check                                      PASS
```

No local LLM eval was applicable; deletion authority and safety are validated
deterministically, never by an LLM.

## Memory and lifecycle

- Shared memory keys read/written: none.
- Lifecycle states: `awaiting_input`, `blocked_for_human_review`, `complete`.
- Risk class: destructive local deletion, exact human confirmation required.

## Known weaknesses

- Project deletion intentionally does not delete a finished export from
  `~/Music/soul-music`; any future finished-library deletion needs a separate brief.
- A reference used by a Fusion must first be unlinked through a future reviewed
  Fusion-management operation; dependency protection is fail-closed today.

## Safety and human review checklist

```text
Persistent/background behavior added: no
Confirmation gate weakened: no
Skill-private memory added: no
Bounded execution: one project (5,000 files / 10 GiB) or one reference
[ ] Preview scopes match the intended deletions
[ ] External finished-export retention is correct
[ ] Dependency and active-work blockers are correct
[ ] Dashboard wording is clear
[ ] Approve candidate for commit/merge
```
