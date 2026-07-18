# Music Generation Timing and Prompt Alignment Review

Status: candidate implementation verified; liquid-DnB listening review pending

## Implemented

- Persisted model, FLAC, MP3, and total generation timings on new candidates.
- Displayed total generation time and a phase breakdown in candidate cards.
- Limited new and revised captions to 512 characters while preserving legacy project readability.
- Corrected instrumental conditioning to exact `[Instrumental]`.
- Corrected runtime-input validation so exact `[Instrumental]` is accepted only after the human-facing instrumental project has stored an empty lyrics field.
- Moved staging creation after runtime-input validation so rejected input cannot leave an empty partial candidate.
- Corrected the Vulkan request language key to `vocal_language`.
- Narrowed Soul-assisted reference and revision captions toward one coherent genre center and concise compatible directions.
- Retained batch size one and every existing exact generation gate.

## Files changed

- `lib/soul_core/music_generation_service.rb`
- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/music_vulkan_generation_backend.rb`
- `lib/soul_core/music_reference_synthesis_service.rb`
- `lib/soul_core/music_revision_draft_service.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- deterministic verification and documentation files

## Commands and results

- Ruby syntax checks for all changed services — PASS
- `node --check assets/dashboard/dashboard.js` — PASS
- `ruby scripts/verify-music-studio-a2.rb` — PASS (32 checks)
- `ruby scripts/verify-music-studio-a3.rb` — PASS (16 checks)
- `ruby scripts/verify-music-core-vulkan-feasibility.rb` — PASS (34 checks)
- `ruby scripts/verify-music-reference-synthesis-a5.rb` — PASS (30 checks)
- `ruby scripts/verify-music-revision-draft.rb` — PASS (18 checks)
- `ruby scripts/verify-dashboard-click-approvals.rb` — PASS (6 checks)
- `git diff --check` — PASS

## Live listening projects

Created without starting generation:

- `music_7178899052d93a4e` — Afterimage Current; 180 seconds; F# minor; 174 BPM; 469-character caption
- `music_1758b06b1f62afd5` — Sun Through Static; 180 seconds; D major; 172 BPM; 511-character caption

Both are instrumental, use liquid drum and bass as the only primary genre, store no human lyrics, and resolve to exact `[Instrumental]` in the generation digest.

## Local LLM evaluation

None. Prompt limits and runtime-field mappings are deterministic. Musical usefulness requires listening review.

## Known weaknesses

- Existing candidates cannot be assigned historical timing retroactively.
- Total time includes bounded validation and artifact inspection not represented as separate phases.
- The pinned C++ runtime cannot combine a true instrumental flag with an independent temporal marker script.
- Caption quality remains probabilistic within the corrected contract.
- Soul does not yet expose repainting or a slower Base/SFT final-quality lane.

## Memory and lifecycle

- Memory keys: none.
- Lifecycle states remain unchanged.
- Persistent processes: none.

## Human review checklist

- [ ] A new candidate displays plausible total and phase timing.
- [ ] Instrumental generation input contains exact `[Instrumental]` and `vocal_language: unknown` at runtime.
- [ ] Liquid-DnB tests remain centered on one genre and produce no vocals.
- [ ] Existing legacy candidates remain inspectable.
