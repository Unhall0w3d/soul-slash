# Long-form Mix Studio A1 Listening Render Review

Status: candidate-complete; Operator listening review required

## Implementation summary

Mix Studio can now render one immutable mix plan into a private listening
candidate. The exact source receipts, all four files in every finished export,
the plan, transition timing, render profile, destination, and expected outputs
are digest-bound before execution.

The foreground renderer applies the sealed trims and linear crossfades through
FFmpeg, writes a 48 kHz stereo FLAC and 320 kbps MP3, verifies both with
FFprobe, records checksums and a receipt, and exposes authenticated ranged audio
playback in the dashboard. It does not accept, publish, or final-export the mix.

The plan detail also supports title correction without rewriting history. A
revised title creates a child immutable plan with identical intent, sources,
trims, crossfades, and transition notes; the original plan and its evidence
remain intact.

## Files changed

- `lib/soul_core/long_form_mix_render_service.rb` (new)
- `scripts/verify-long-form-mix-render-a1.rb` (new)
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `docs/guides/MIX_STUDIO.md`
- `scripts/verify-long-form-mix-a0.rb`
- `Makefile`
- `README.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/soul/LONG_FORM_MIX_A1_LISTENING_RENDER_BRIEF.md` (new)
- `docs/assessments/LONG_FORM_MIX_A0_REVIEW.md`

Private, ignored review evidence was created beneath
`Soul/private/mix_renders`; no creative artifact was added to git.

## Commands run

- `ruby -c lib/soul_core/long_form_mix_render_service.rb`
- `ruby -c scripts/verify-long-form-mix-render-a1.rb`
- `node --check assets/dashboard/dashboard.js`
- `make verify-long-form-mix`
- `make verify-long-form-mix-render`
- `ruby scripts/verify-phase12b-in-process-application-api.rb`
- `ruby scripts/verify-dashboard-self-improvement-navigation.rb`
- `git diff --check`
- a real preview and exact execution for `mix_a2f8c3a1436c51b8`
- `ffprobe` on the real FLAC and MP3
- `sha256sum -c checksums.sha256` on the real render
- `ffmpeg` volume and transition-window silence inspection

## Deterministic test results

The focused A0 and A1 verifiers passed. A1 covers the exact confirmation
phrase, digest binding, source drift, idempotency, atomic output, FFmpeg graph,
48 kHz stereo output, FFprobe validation, manifest integrity, authenticated
ranged playback, and facade dispatch.

The broader Phase 12B verifier reached its repository-curation check while the
new verifier was intentionally untracked. This is resolved by the candidate
commit; no application regression failed before that curation boundary.

## Real render evidence

`The Rooms Begin Listening` rendered from three finished, keep-reviewed
exports.

- Plan: `mix_a2f8c3a1436c51b8`
- Duration: 423.600 seconds
- Lossless output: FLAC, 48 kHz, stereo
- Listening output: MP3, 48 kHz, stereo
- FLAC SHA-256:
  `c227c1748b54b1ffda4377b3bb378b007e20036a170fe10037ac300a85164f0a`
- MP3 SHA-256:
  `211213d30e7c8338b1c030d976e12c07599b6912be560c275d20357a62b60f9d`
- All manifest checks passed.
- No silence was detected around either transition window at the bounded
  threshold used for inspection.

## Local LLM eval results

Not run. This slice is deterministic media assembly and integrity validation;
LLM behavior does not authorize or evaluate it.

## Known weaknesses

- Human listening is still required to judge whether the two transitions work
  musically.
- The transparent peak limiter prevents transition clipping but is not release
  mastering or distribution loudness normalization.
- The listening render is synchronous and foreground-only by design.
- A final acceptance/export contract remains a later slice.
- This slice sequences audio only; visual-loop sequencing remains separate.

## Memory keys added or used

None.

## Task lifecycle states touched

- `complete`
- `awaiting_input`
- `blocked_for_human_review`

## Risk classification

Class 2/3: bounded local media rendering from immutable reviewed inputs. No
privileged action, persistence, external publication, or destructive source
mutation.

## Human review checklist

- [x] Exact source and plan scope is previewed before rendering
- [x] Click authorization binds to one exact digest
- [x] Finished-export receipts and all recorded file hashes are revalidated
- [x] Output is private, atomic, non-overwriting, and checksum verified
- [x] Authenticated ranged playback is implemented
- [x] Real output duration, channels, sample rate, and checksums are verified
- [ ] Listen through the complete candidate
- [ ] Review the transition near 00:37.8–00:39.3
- [ ] Review the transition near 02:56.4–02:58.9
- [ ] Decide whether to accept the sequence or create a revised immutable plan
