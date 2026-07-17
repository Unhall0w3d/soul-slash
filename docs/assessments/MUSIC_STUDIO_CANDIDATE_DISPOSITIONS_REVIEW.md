# Music Studio candidate dispositions review

Status: candidate-complete; requires human review.

## Implemented

- Linked candidates marked `revise` collapse to playable older versions.
- Existing reviews populate the review editor instead of resetting its values.
- Rejected-candidate deletion uses preview, exact digest, exact phrase, actual
  artifact validation, and a small lineage receipt.
- Kept-candidate export uses exact candidate input, completed vocal transcription
  where applicable, private atomic copying, digest verification, non-overwrite,
  and idempotent receipts.
- Finished vocal folders contain FLAC, MP3, metadata, a human-readable song sheet,
  and formatted machine-heard lyrics. Instrumentals omit the lyric file.
- Dashboard controls expose each action only after its corresponding recorded
  review disposition.

## Files changed

- `lib/soul_core/music_candidate_disposition_service.rb`
- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-music-candidate-dispositions.rb`
- this brief and review artifact

## Commands and deterministic results

- Ruby and JavaScript syntax checks: passed.
- `ruby scripts/verify-music-candidate-dispositions.rb`: passed.
- The verifier covers vocal transcription gating, wrong confirmations, linked
  descendants, actual deletion, retained lineage, exact revised metadata,
  digest-verified export, private permissions, idempotency, instrumental export,
  application dispatch, and absence of automatic browser behavior.
- Music Studio A3 regression: passed.

## Local LLM eval

Not applicable. This slice performs deterministic disposition, lineage, path,
digest, and file operations. No LLM decides whether a candidate is kept,
revised, rejected, deleted, or exported.

## Known weaknesses

- Sanitized title collisions stop safely; folder renaming/version selection is a
  future library-management concern.
- A finished export cannot yet be deleted from the dashboard. A candidate with
  such an export cannot be rejected until that separate reviewed operation exists.
- Machine-heard lyrics remain fallible evidence and are labeled through metadata;
  they are not treated as the authoritative intended lyric sheet.
- YouTube publication is deliberately excluded.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Lifecycle states: `awaiting_input`, `blocked_for_human_review`, `complete`.
- Mutations: `music_candidate_deleted`, `finished_song_exported`.

## Risk classification

Confirmed permanent local deletion and confirmed local file export. No privilege,
new persistence, daemon, listener, scheduler, automatic retry, cloud transfer, or
external publication.

## Human review checklist

- [ ] A reviewed revision collapses only after its linked replacement exists.
- [ ] The collapsed card retains identity and playback and can be expanded.
- [ ] Reject requires an exact destructive preview and phrase.
- [ ] Confirmed reject removes the candidate from the list and leaves no media or
      transcription in project generations.
- [ ] Keep refuses vocal export until transcription exists.
- [ ] Keep requires an exact export preview and phrase.
- [ ] The finished folder appears under `~/Music/soul-music/` with correct files.
- [ ] Metadata reflects the selected candidate's BPM, key, time, seed, Sound and
      Structure, Title, Intent, Duration, Mode, and Rights Status.
- [ ] Repeating export does not overwrite files.
