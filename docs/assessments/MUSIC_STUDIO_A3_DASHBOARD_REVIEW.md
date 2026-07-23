# Music Studio A3 Dashboard Review

Status: candidate-complete, awaiting Operator visual and workflow review

Date: 2026-07-17

## What was implemented

- Added the fifth dashboard tab, Music Studio, in the established Soul visual system.
- Exposed authenticated project listing, exact project inspection, immutable project creation, and read-only resource inventory.
- Added exact digest-bound generation preview and one NDJSON foreground generation stream with bounded model-output progress.
- Initial composition generation and revision generation now share one live stage/message treatment with the cyan activity pulse used by Visual Studio. The indicator resolves on success, failure, or cancellation while the terminal result remains visible.
- Reworked the existing loopback server from sequential handling to at most 24 tracked request-scoped threads so an explicit Operator action can reach an active stream. Transient bursts wait at most two seconds for a slot before receiving `429`; shutdown closes sockets and joins threads.
- Changed inactive dashboard audio and video controls to load on demand rather than eagerly opening metadata range requests.
- Added disconnect/timeout cleanup that terminates the exact owned music process group and releases its lease. No queue, detached worker, automatic model loading, or retry loop was added.
- Added authenticated MP3 playback and FLAC access through identifier-validated, symlink-rejecting project paths.
- Added project-local candidate review evidence for rating, disposition, musical quality, prompt adherence, vocal adherence, lyric adherence, and notes. Revised assessments preserve the prior digest-named revision instead of overwriting evidence.

## Files changed

- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `config/music_candidate_review_schema.json`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/dashboard_server.rb`
- `lib/soul_core/music_generation_service.rb`
- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/phase12c_foreground_dashboard_assessor.rb`
- `scripts/verify-phase12c-foreground-dashboard.rb`
- `scripts/verify-music-studio-a3.rb`
- `Makefile`
- Music A3 brief, foreground-dashboard documentation, and this artifact.

## Commands run

- Ruby syntax checks on changed Ruby files.
- `node --check assets/dashboard/dashboard.js`
- `ruby scripts/verify-music-studio-a2.rb`
- `ruby scripts/verify-music-studio-a3.rb`
- `ruby scripts/verify-phase12c-foreground-dashboard.rb`
- Live read-only `music.projects.list` through `ApplicationFacade` against the retained First Signal project.
- `git diff --check`

## Deterministic test results

The A2 core regression passes. The new A3 verifier passes project-object contract validation, traversal rejection, review persistence, artifact allowlisting, client-abandonment process-group termination, bounded request concurrency, explicit authenticated routes, dashboard surface presence, timer/remote-dependency exclusion, and brief boundaries.

Recorded candidate reviews remain revisable. A kept candidate now exposes a
direct **Re-mark as revise** action; the corrected review uses the existing
validated review operation, and the prior keep record remains in immutable
review history.

Lyric-only closing corrections no longer dead-end when the local model returns
an unchanged or over-limit caption. If exact evidence identifies the final
intended lyric as incomplete, one deterministic under-512-character arrangement
adjustment is offered for human editing. The model is not called again and no
audio starts automatically.

The Phase 12C verifier passes its updated bounded-concurrency contract. Its recursive repository-curation regression initially reports the intentionally untracked A3 verifier as a review candidate; that check becomes clean after the candidate files are intentionally staged.

## Local LLM eval results

Not run. A3 changes are interface, transport, path, lifecycle, and foreground-process control behavior. The known vocal result comes from the prior owner-reviewed live ACE-Step run, not an LLM safety eval.

## Known weaknesses

- The first retained vocal candidate contains acceptable music but no audible lyrics. A3 records this distinction; it does not claim to solve ACE-Step vocal adherence.
- Existing project inputs are immutable in A3. The editor creates a new project rather than rewriting a generated project's lineage.
- Progress is stage-accurate but not a percentage estimate. Display-only output is capped at 128 queued chunks and may be dropped while the complete generation log remains bounded and retained.
- MP3/FLAC responses implement a single bounded byte range for browser seeking. Playback and seeking still need device review, especially on mobile Safari.
- A sustained workload that occupies all 24 request slots for more than two seconds still receives `429` by design; the correction absorbs ordinary browser bursts rather than removing the ceiling.
- Cancellation is deterministically proven against an owned subprocess and remains exact-confirmation gated, but has not yet been used during a live ACE-Step generation from the dashboard.
- Failed and canceled partial candidates remain quarantined for later reviewed cleanup.

## Memory keys added or used

None. Project and review records are bounded task artifacts in the existing ignored Music project store. Nothing is promoted into shared Soul memory.

## Task lifecycle states touched

- `complete`: project listing, creation, inspection, resource inspection, and review recording.
- `awaiting_input`: invalid project, candidate, and review fields.
- `failed`: transport or bounded subprocess failures.
- `canceled`: timeout, disconnect cleanup, or exact Operator cancellation.
- `blocked_for_human_review`: generation previews, resource conflicts, integrity failures, and completed candidates awaiting listening review.

## Risk classification

- Authenticated read-only project/audio inspection: Class 1.
- Project and review writes: Class 2.
- Foreground GPU generation: Class 2.
- Exact owned-process cancellation and disconnect cleanup: Class 3 destructive-to-owned-task.
- Bounded request concurrency inside the approved loopback dashboard listener: Class 5 transport-sensitive change.

## Human review checklist

- [ ] Confirm the Music Studio visual hierarchy at desktop, ultrawide, and phone widths.
- [ ] Confirm the retained First Signal project and candidate appear correctly.
- [ ] Play the MP3 and open the FLAC from an authenticated session.
- [ ] Record the known lyric-adherence failure and confirm it persists after refresh.
- [ ] Create a new project and inspect its exact generation scope.
- [ ] Approve one live dashboard generation and observe stage progress.
- [ ] Optionally exercise exact cancellation during a live generation.
- [ ] Confirm no generation survives tab abandonment or dashboard shutdown.
- [ ] Approve A3 for merge only after visual and live workflow review.
