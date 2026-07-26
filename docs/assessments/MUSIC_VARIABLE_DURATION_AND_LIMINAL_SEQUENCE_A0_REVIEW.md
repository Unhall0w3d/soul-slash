# Music Variable Duration and Liminal Sequence A0 Review

Status: candidate-complete; human listening and dashboard review pending

## Implemented

- Added an explicit pilot-only `variable_duration_v1` marker.
- Bounded variable pilots to exact whole seconds from 30 through 300, while
  retaining ten minutes as a separate fixed production option.
- Preserved historical 210-second qualification reproducibility while including
  210 seconds in the new continuous project range.
- Added deterministic rejection coverage for unmarked, out-of-range, and
  fixed-duration-marked requests, including exact 144-second (2:24) and
  continuous-range 210-second preview fixtures.
- Prepared a five-part local music and native-video sequence for later Operator
  review.
- Added end-to-end project validation, Chat planning, Core status, schema,
  Dashboard entry, and documentation for exact 30–300-second targets plus the
  fixed 600-second option.
- Prefill a selected Visual project's stored prompt into the editable native
  text-to-video direction without beginning a render.

## Files changed

- `config/music_vulkan_models.json`
- `scripts/soul-music-vulkan-pilot`
- `scripts/verify-music-core-vulkan-feasibility.rb`
- `docs/soul/MUSIC_VARIABLE_DURATION_QUALIFICATION_A0_BRIEF.md`
- `docs/assessments/MUSIC_VARIABLE_DURATION_AND_LIMINAL_SEQUENCE_A0_REVIEW.md`
- `config/music_project_schema.json`
- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/conversation_creative_planner.rb`
- `lib/soul_core/core_orchestration_service.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `scripts/verify-music-studio-a2.rb`
- `scripts/verify-music-studio-a3.rb`
- `scripts/verify-core-orchestration.rb`
- `README.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/guides/MUSIC_STUDIO.md`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`

## Commands run and deterministic results

- `ruby -c scripts/soul-music-vulkan-pilot` — PASS.
- `ruby -c scripts/verify-music-core-vulkan-feasibility.rb` — PASS.
- `ruby scripts/verify-music-core-vulkan-feasibility.rb` — PASS.
- `ruby scripts/verify-music-studio-a2.rb` — PASS.
- `ruby scripts/verify-music-studio-a3.rb` — PASS.
- `ruby scripts/verify-core-orchestration.rb` — PASS.
- `ruby scripts/verify-conversational-creative-workflow.rb` — PASS (60 checks).
- `ruby scripts/verify-visual-studio-native-video.rb` — PASS.
- `node --check assets/dashboard/dashboard.js` — PASS.
- `git diff --check` — PASS.
- Live 43-second qualification — PASS: one 42.8-second, 48 kHz stereo WAV;
  214/215 expected audio codes, non-degenerate, 10.51-second wall time, no
  resident ACE process.
- Live 248-second qualification — PASS: one 247.84-second, 48 kHz stereo WAV;
  1,239/1,240 expected audio codes, non-degenerate, 40.01-second wall time, no
  resident ACE process.

## Local LLM eval results

No local LLM eval is used for authorization or safety approval. Creative briefs
are human-review candidates.

## Known weaknesses

- Successful technical pilots cannot establish musical quality.
- Separate music and motion artifacts do not yet form an editable long-form
  timeline.
- Native text-to-video remains limited to a reviewed 4-, 8-, or 12-second loop
  candidate rather than unique full-song footage.

## Memory keys added or used

None.

## Task lifecycle states touched

- `awaiting_input` for invalid or unmarked variable duration.
- `blocked_for_human_review` for an exact pilot gate and completed pilot.
- `failed` for bounded runtime failure.

## Risk classification

Local compute and temporary storage, medium. No persistent process, external
publication, destructive action, or automatic promotion is introduced.

## Human review checklist

- [ ] Listen to the representative short variable-duration pilot.
- [ ] Listen to the representative long variable-duration pilot.
- [ ] Assess coherence, repetition, endings, and transition utility.
- [ ] Inspect all five music briefs in Music Studio.
- [ ] Inspect all five visual briefs in Visual Studio.
- [ ] Confirm visual prompts form one coherent sequence without copying frames.
- [ ] Decide whether variable duration should be promoted to the production UI.
- [ ] Decide the first timeline/editor requirements for a longer-form mix.
