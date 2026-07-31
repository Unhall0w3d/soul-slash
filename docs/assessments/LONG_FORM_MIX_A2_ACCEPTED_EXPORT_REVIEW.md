# Long-form Mix Studio A2 Accepted Export Review

Status: candidate-complete; Operator listening and Dashboard review required

## Implementation summary

A2 adds the missing human listening disposition and exact accepted-audio export
to Mix Studio. Reviews record sequence cohesion, transition quality, rating,
disposition, and notes against the exact A1 render. Correcting a review
preserves bounded prior history.

Only the latest `keep` review can preview `EXPORT_ACCEPTED_MIX`. Execution binds
the immutable plan, review identity, render scope, FLAC/MP3 hashes,
destination, and expected outputs. The resulting package is non-overwriting
and contains the verified A1 FLAC/MP3, JSON metadata, Markdown summary, and a
checksum manifest.

## Files changed

- `lib/soul_core/long_form_mix_finalization_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-long-form-mix-finalization-a2.rb`
- `Makefile`
- `README.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/guides/MIX_STUDIO.md`
- `docs/soul/LONG_FORM_MIX_A2_ACCEPTED_EXPORT_BRIEF.md`
- `config/project_tracker_seed.json`

## Commands run

```text
make verify-long-form-mix-finalization
make verify-long-form-mix
make verify-long-form-mix-render
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-dashboard-self-improvement-navigation.rb
node --check assets/dashboard/dashboard.js
git diff --check
```

## Deterministic results

- review input and rating bounds pass;
- reject/revise cannot export;
- corrected reviews retain prior evidence;
- exact phrase and digest are required;
- render drift fails closed;
- tampered review identities cannot influence export paths;
- accepted packages are immutable and idempotent;
- copied FLAC/MP3 and all sidecars verify against checksums;
- facade and Dashboard operations are registered;
- mastering, visual assembly, and publication remain explicitly excluded.

## Local LLM evals

Not run. This is a deterministic media-review and filesystem export contract.
LLM output cannot supply human listening acceptance.

## Known weaknesses

- The Operator has not yet completed the A2 listening review in the live
  Dashboard.
- Accepted audio is the verified A1 render; it is not release mastering or
  loudness normalization.
- Visual-loop sequencing and combined audio/video export remain a later slice.

## Memory keys

None.

## Lifecycle states

- `complete`
- `awaiting_input`
- `blocked_for_human_review`

## Risk classification

Class 2/3: bounded local review evidence and exact non-destructive copies under
configured private/music roots. No privilege, persistence, publication, or
source mutation.

## Human review checklist

- [x] Human review is distinct from deterministic verification
- [x] Earlier reviews remain preserved
- [x] Non-keep dispositions cannot export
- [x] Exact review/render digest gate is preserved
- [x] Source drift and destination collision fail closed
- [x] Accepted package checksums are deterministic
- [ ] Listen through the selected candidate
- [ ] Record the live disposition and notes
- [ ] Preview and, if kept, inspect one real accepted-audio package
- [ ] Decide whether the audio foundation is validated before visual sequencing
