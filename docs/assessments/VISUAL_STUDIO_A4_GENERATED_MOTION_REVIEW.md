# Visual Studio A4 generated motion review

## What was implemented

- Added a production image-to-video lane backed by the separately pinned Wan 2.2 TI2V Vulkan runtime.
- Required a kept still before preview or execution.
- Added exact preview/execute binding for source digest, prompt, seed, profile, dimensions, frame count, and frame rate.
- Added immutable private WebM candidates, bounded logs, review records, authenticated range-capable playback, and newest-first project projection.
- Added exact preview/execute deletion for disposable motion studies.
- Added explicit binding of a kept motion candidate to an exact Music candidate.
- Extended Music Studio to play reviewed motion and create a full-duration H.264/AAC MP4 by repeating the exact short clip and muxing the exact lossless audio.
- Preserved the qualified still-image companion route.

## Files changed

- `lib/soul_core/visual_studio_service.rb`
- `lib/soul_core/music_visual_companion_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-visual-studio-generated-motion.rb`
- `scripts/verify-visual-studio-a2.rb`
- `scripts/verify-music-visual-companion.rb`
- `docs/soul/VISUAL_STUDIO_A4_GENERATED_MOTION_BRIEF.md`
- `docs/assessments/VISUAL_STUDIO_A4_GENERATED_MOTION_REVIEW.md`

## Commands run

- Ruby syntax checks for every changed service and transport file.
- `node --check assets/dashboard/dashboard.js`
- `ruby scripts/verify-visual-studio-generated-motion.rb`
- `ruby scripts/verify-visual-studio-a2.rb`
- `ruby scripts/verify-music-visual-companion.rb`
- `ruby scripts/verify-visual-motion-qualification.rb`
- `git diff --check`

## Deterministic test results

- Generated-motion vertical slice: passed.
- Visual Studio A2 regression: passed.
- Music visual companion regression and generated-motion mux fixture: passed.
- Motion runtime qualification verifier: passed before production integration; rerun required in final verification.

## Local LLM eval results

- Not applicable. This slice contains deterministic lifecycle, media, and authorization behavior; no model output is used to decide safety or approval.

## Known weaknesses

- The image-guided production profile remains a short 832×480 study. Text-only video is qualified separately by the A5 native-video lane; longer unique-duration generation remains unqualified.
- Full-duration videos repeat the accepted short clip; loop-boundary quality remains a human aesthetic decision.
- TAE avoids the full-VAE device loss observed during qualification, but its decode fidelity is lower than the full VAE.
- Browser navigation can detach from the progress stream. The server-side request remains bounded, but a durable creative-job ledger is a separate future slice.

## Memory keys added or used

- None.

## Task lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `canceled` through bounded command interruption
- `blocked_for_human_review`

## Risk classification

- Local write and local GPU inference.
- No privilege escalation, persistence, listener, network upload, or external publication added.
- Destructive project/candidate deletion protections are unchanged.

## Human review checklist

- [ ] Confirm motion resources report ready in Music Core or AMD-Free Core.
- [ ] Generate one motion study from a kept still and confirm the page remains responsive.
- [ ] Inspect geometry stability, motion coherence, color banding, and loop boundary.
- [ ] Record a motion review and confirm only `keep` unlocks Music binding.
- [ ] Bind to an exact song candidate and render the full-duration preview.
- [ ] Confirm the MP4 has the expected audio, duration, resolution, and repeated reviewed motion.
- [ ] Confirm no upload or publication occurs.
