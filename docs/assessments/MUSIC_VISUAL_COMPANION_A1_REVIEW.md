# Music Visual Companion A1 Review

Status: candidate implementation verified; human loop and three-minute preview review pending

## Implemented

- Exact candidate/audio binding for an approved project-local source image.
- Immutable provenance and artifact digests.
- Bounded 12-second procedural environmental loop.
- First-to-last-frame PSNR seam evidence.
- Three-minute H.264/AAC preview with intro/outro fades and exact FLAC audio.
- Authenticated range-capable image/video delivery.
- Music Studio controls for all three gates.

## Files changed

- `assets/music_visuals/afterimage-current-base-v1.{json,png}`
- `lib/soul_core/music_visual_companion_service.rb`
- application contract, facade, HTTP transport, dashboard JavaScript/CSS
- deterministic verification and this review artifact

## Deterministic verification

- Ruby syntax checks for the service, facade, contract, and HTTP application — PASS
- `node --check assets/dashboard/dashboard.js` — PASS
- `ruby scripts/verify-music-visual-companion.rb` — PASS (6 checks)
- `ruby scripts/verify-music-studio-a2.rb` — PASS (32 checks)
- `ruby scripts/verify-music-studio-a3.rb` — PASS (16 checks)
- `git diff --check` — PASS

## Live proof state

- Project: `music_7178899052d93a4e` — Afterimage Current
- Candidate: `candidate_29ae0cdeac32f154`
- Visual: `visual_686e91d516c637f2`
- Source image: 1,970,412 bytes; SHA-256 `e0acee944e4b21c9f7e5f480c46518646aecf6695ae017a1f8e3a6718c044ba2`
- Loop: 12 seconds, 1280×720, 30 fps, 1,784,951 bytes
- First-to-last-frame PSNR: 45.541 dB
- Three-minute preview: deliberately not rendered before human loop review

## Local LLM evaluation

None. A1 performs no LLM call.

## Known weaknesses

- The first profile provides subtle water and camera motion only; mist and beacon animation remain future refinements.
- PSNR is continuity evidence, not an aesthetic judgment.
- One twelve-second loop may become perceptibly repetitive; the three-minute human review establishes that baseline.
- Source generation is imported rather than invoked by Soul in A1.

## Memory and lifecycle

- Shared memory keys: none.
- States touched: `complete`, `awaiting_input`, `blocked_for_human_review`.
- Persistent services added: none.

## Human review checklist

- [ ] Play the twelve-second loop across at least three boundaries.
- [ ] Confirm the water motion reads as intentional and the seam is unobtrusive.
- [ ] Review the complete three-minute preview for repetition fatigue.
- [ ] Confirm fade timing supports the music.
- [ ] Record refinements before increasing source-loop or mix duration.
