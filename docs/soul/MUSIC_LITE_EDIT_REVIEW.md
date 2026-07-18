# Music Lite Edit candidate review

## What was implemented

- A browser-rendered source waveform with millisecond start/end controls and a
  bounded selection audition.
- Exact trim preview and click-authorized execution for accepted, already
  exported candidates.
- Immutable-source FFmpeg trimming into a new FLAC, MP3, and digest-bound edit
  receipt under the finished song's `edits/` directory.
- Explicit UI language separating edge cleanup from revision-worthy internal
  omissions, transitions, splices, and arrangement changes.

## Files changed

- `lib/soul_core/music_candidate_trim_service.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/application_contract.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `docs/soul/MUSIC_LITE_EDIT_BRIEF.md`
- `docs/soul/MUSIC_LITE_EDIT_REVIEW.md`
- `scripts/verify-music-lite-edit.rb`

## Commands and deterministic results

- `make verify-music-lite-edit` — passed (10 checks).
- `ruby scripts/verify-music-candidate-dispositions.rb` — passed.
- `ruby scripts/verify-music-studio-a3.rb` — passed.
- `ruby scripts/verify-dashboard-click-approvals.rb` — passed.
- `ruby scripts/verify-music-revision-draft.rb` — passed.
- `ruby scripts/verify-music-reference-synthesis-a5.rb` — passed.
- `ruby scripts/verify-music-studio-a2.rb` — passed.
- `ruby -c` for the new service and modified application files — passed.
- `node --check assets/dashboard/dashboard.js` — passed.
- `git diff --check` — passed.
- Read-only preview against Weather in the Wiring at `0.000–174.240`
  produced an exact gate and destination without mutation.

## Local LLM eval results

Not used. This slice is deterministic audio/file manipulation and browser UI;
an LLM cannot authorize or validate its safety boundary.

## Known weaknesses

- Lite Edit supports source-edge trimming only. There are intentionally no
  internal cuts, splices, fades, amplification, or edit-of-edit operations.
- The original accepted song must be exported first.
- The browser decodes the MP3 only after the Operator opens Lite Edit; very long
  future formats may warrant a server-generated bounded waveform envelope.

## Memory keys added or used

None.

## Task lifecycle states touched

- `awaiting_input`
- `blocked_for_human_review`
- `complete`

## Risk classification

Local write. The source and previous finished export are immutable. Output is a
new, private, digest-bound subdirectory and exact replay is idempotent.

## Human review checklist

- [ ] Weather in the Wiring can select approximately `0.000–174.240` seconds.
- [ ] Selection audition stops at the chosen end boundary.
- [ ] Preview identifies the immutable candidate source and exact output path.
- [ ] Applying creates FLAC and MP3 under the original export's `edits/` folder.
- [ ] The original candidate and finished export remain unchanged and playable.
- [ ] Teeth of the Signal still presents missing bridge/internal transition
      problems as revision evidence rather than claiming trimming can fix them.
