# Music Studio Duration Constraint Review

Status: candidate-complete for human review

## What was implemented

- Made 30, 90, and 180 seconds the only supported durations for newly created
  music projects, matching the dashboard and pinned music pilot.
- Kept bounded 10–180-second validation only when reading legacy project and
  candidate records, so old local data remains inspectable.
- Kept revision duration authoritative to the source project. A revision may
  alter its arrangement, but it cannot silently change the requested runtime.
- Normalized a complete over-budget section plan proportionally to the project's
  authoritative duration before preview. Missing or reordered required sections
  still fail closed for another bounded draft attempt.

## Files changed

- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/music_revision_draft_service.rb`
- `scripts/verify-music-studio-a2.rb`
- `scripts/verify-music-revision-draft.rb`
- `docs/soul/MUSIC_STUDIO_A2_PROJECT_AND_RESOURCE_BRIEF.md`
- `docs/soul/MUSIC_STUDIO_DURATION_CONSTRAINT_REVIEW.md`

## Commands and deterministic results

- `ruby scripts/verify-music-studio-a2.rb` — passed, including all three presets,
  unsupported creation, legacy reads, revision gates, and bounded generation.
- `ruby scripts/verify-music-revision-draft.rb` — passed, including proportional
  timing correction and exact repeated-section coverage.
- `ruby scripts/verify-music-studio-a3-vocal-analysis.rb` — passed, including
  repeated-section lyric alignment and evidence review behavior.
- `ruby -c lib/soul_core/music_project_store.rb` — syntax OK.
- `ruby -c lib/soul_core/music_revision_draft_service.rb` — syntax OK.
- `node --check assets/dashboard/dashboard.js` — passed.
- `git diff --check` — passed.

## Local LLM eval results

No local LLM eval is used as approval. The observed 208-second draft is retained
as behavioral evidence that model-authored section arithmetic needs deterministic
application enforcement.

## Known weaknesses

- Proportional timing correction preserves section order and total duration but
  cannot guarantee that the generator will render every section or lyric.
- Legacy projects with non-preset durations are readable and generatable for
  compatibility; the dashboard does not offer creation of additional projects at
  those durations.

## Memory keys added or used

None.

## Task lifecycle states touched

- `awaiting_input` for unsupported new project duration.
- `blocked_for_human_review` for a valid revision preview.
- `failed` for bounded drafting or generation failures.

## Risk classification

Low. Validation is narrowed for new project creation and remains bounded for
legacy reads. No service, scheduler, watcher, network listener, or background
process is added.

## Human review checklist

- [ ] Confirm new projects accept only 30, 90, or 180 seconds.
- [ ] Confirm an older bounded project remains readable.
- [ ] Confirm revision previews preserve the source project's duration.
- [ ] Confirm over-budget section timing is visibly normalized rather than used
      as an unsupported runtime.
- [ ] Confirm no generation starts before the existing exact human gate.
