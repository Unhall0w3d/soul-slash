# Visual Studio A5 native-video review

## What was implemented

- Pinned FastWan 2.2 TI2V 5B FullAttn Q6_K as a separate native text-to-video profile.
- Added resource verification for the exact native diffusion model plus the already pinned shared UMT5 and TAE files.
- Added exact preview/execute operations with a 1,050-second timeout, three-step Euler/LCM schedule, no source image, and no automatic retry.
- Kept diffusion on AMD Vulkan while assigning the 97-frame TAE decode to bounded CPU VAE tiling. This avoids a single 18.6 GB Vulkan decode buffer on the 16 GB reference GPU without reducing frame rate, dimensions, or output quality.
- Reused immutable motion candidates, review, deletion, authenticated playback, Music binding, and full-duration companion rendering.
- Added a distinct Visual Studio scene-direction panel and clear text-to-video lineage labels.
- Added explicit four-, eight-, and twelve-second profiles plus a review-led native revision lane. A recorded `revise` review supplies the initial revised direction; the Operator previews a new seed and exact duration before one new immutable candidate is rendered.
- The twelve-second profile keeps inference at the proven 193-frame workload and derives its 24 fps review artifact from a 16 fps source through one bounded local optical-interpolation pass.
- Still generation, guided revisions, image-guided motion, native scenes, and native-scene revisions now share Music Studio's live stage/message treatment and cyan activity pulse. A terminal failure remains visible instead of being replaced by a false success message.
- Added a process-owned exclusive `amd-vulkan-generation` lease shared by Music
  and Visual Studio. Competing renders fail immediately with an occupied-resource
  result; nothing is queued or preempted, and the lease releases in `ensure`.
- Raised the existing dashboard's hard request ceiling from 24 to 48 so a
  foreground native render stream can coexist with bounded reviewed audio and
  video ranges without starving Operator actions; the two-second admission
  wait and HTTP 429 overload behavior remain intact.

## Files changed

- `config/visual_native_models.json`
- `lib/soul_core/visual_studio_service.rb`
- `lib/soul_core/model_runtime_lease_store.rb`
- `lib/soul_core/music_resource_coordinator.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `Makefile`
- `scripts/verify-visual-studio-native-video.rb`
- `docs/soul/VISUAL_STUDIO_A5_NATIVE_VIDEO_BRIEF.md`
- `docs/assessments/VISUAL_STUDIO_A5_NATIVE_VIDEO_REVIEW.md`
- `lib/soul_core/dashboard_server.rb`
- `lib/soul_core/phase12c_foreground_dashboard_assessor.rb`
- `scripts/verify-music-studio-a3.rb`
- `scripts/verify-phase12c-foreground-dashboard.rb`
- `docs/soul/MUSIC_STUDIO_A3_DASHBOARD_BRIEF.md`
- `docs/soul/MUSIC_STUDIO_DASHBOARD_CONCURRENCY_REVIEW.md`

## Commands and results

- Initial FastWan AMD/Vulkan pilot: passed; 832×480, 33 frames at 8 fps, valid VP8 WebM, 4.0-second container duration, 395.82-second qualification time and 268.38-second production time. Human review found playback visibly chunky.
- Native-rate FastWan pilot: passed; 832×480, 97 frames at 24 fps, valid VP8 WebM, 4.0-second container duration, 867.78-second renderer time. Human review found it materially smoother and clean.
- Production follow-up initially failed safely during decode: untiled Vulkan decode requested an 18.6 GB compute buffer; spatial tiling alone still requested 11.5 GB plus resident allocations. Explicit `vae=cpu` with VAE tiling passed at the same 832×480, 97-frame, 24 fps scope in 75.643 seconds and produced a valid 4.0-second VP8 WebM candidate for human review.
- `ruby scripts/verify-visual-studio-native-video.rb`: passed.
- `ruby scripts/verify-visual-studio-generated-motion.rb`: passed.
- `ruby scripts/verify-visual-studio-a1.rb`: passed after retained supersession marker.
- `ruby scripts/verify-visual-studio-a2.rb`: passed after retained supersession marker.
- `ruby scripts/verify-music-visual-companion.rb`: passed.
- Ruby and JavaScript syntax checks: passed.

## Local LLM eval results

- Not applicable. Model output is aesthetic evidence for human review, never authorization or safety evidence.

## Known weaknesses

- Four, eight, or twelve seconds are generated natively; long-form output repeats an accepted clip until the separately reviewed multi-shot sequence lane exists.
- Native 24 fps runtime varies materially by runtime build and decode placement. The original qualification took roughly 14½ minutes; the bounded CPU-decode production follow-up completed in 75.643 seconds. The 1,050-second hard timeout remains authoritative.
- The fixed 480p study is for qualification and review, not a claim of high-resolution cinematic generation.
- Multi-shot scene planning and diverse long-form sequencing remain future work.
- The shared lease coordinates Soul-owned foreground work. It cannot prevent an
  unrelated external process from using the AMD GPU.

## Memory and lifecycle

- Memory keys: none.
- Lifecycle states: `complete`, `failed`, `awaiting_input`, `canceled`, `blocked_for_human_review`. A competing Studio render terminates as `blocked_for_human_review`; it does not wait.

## Risk classification

- Local write and bounded local GPU inference. No privilege, persistence, listener, upload, or external publication.

## Human review checklist

- [ ] Confirm native resources report ready in Music Core or AMD-Free Core.
- [ ] Confirm active Music generation blocks Visual generation, and active Visual generation blocks Music generation, without queueing either request.
- [ ] Generate a scene from text and confirm it is not derived from a still.
- [ ] Record a `revise` review, confirm the notes preload the native revision form, and generate a twelve-second revision linked to the original candidate.
- [ ] Inspect coherence, camera motion, geometry, flicker, banding, and loop boundary.
- [ ] Confirm only a kept candidate can bind to music.
- [ ] Render and inspect one three-minute companion using the exact reviewed clip and song.
