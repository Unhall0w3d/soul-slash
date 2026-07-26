# Music Instrumental Timing Guidance Review

## Candidate status

```text
candidate_complete
```

## What changed

Music timing validation is now mode-aware:

- vocal Sound and Structure still rejects exact section-second schedules because
  those belong in the preserved lyrics script;
- instrumental Sound and Structure may include concise second-based movement
  guidance;
- instrumental projects still store no lyrics and generate with exact
  `[Instrumental]`;
- the dashboard disables the instrumental lyrics editor and explains where
  arrangement timing belongs;
- Soul-drafted instrumental revisions use the same rule.

Existing projects and candidates were not rewritten. No generation was started
by this implementation pass.

## Files changed

```text
assets/dashboard/dashboard.js
assets/dashboard/index.html
docs/CURRENT_STATE.md
docs/assessments/MUSIC_INSTRUMENTAL_TIMING_GUIDANCE_REVIEW.md
docs/guides/MUSIC_STUDIO.md
docs/soul/MUSIC_INSTRUMENTAL_TIMING_GUIDANCE_BRIEF.md
lib/soul_core/music_project_store.rb
lib/soul_core/music_revision_draft_service.rb
scripts/verify-music-reference-synthesis-a5.rb
scripts/verify-music-revision-draft.rb
scripts/verify-music-studio-a2.rb
```

## Deterministic verification

```text
ruby scripts/verify-music-studio-a2.rb: pass
ruby scripts/verify-music-studio-a3.rb: pass
ruby scripts/verify-music-revision-draft.rb: pass
ruby scripts/verify-music-reference-synthesis-a5.rb: pass
ruby scripts/verify-conversational-creative-workflow.rb: pass, 60 checks
ruby scripts/verify-dashboard-click-approvals.rb: pass
node --check assets/dashboard/dashboard.js: pass
ruby -c lib/soul_core/music_project_store.rb: pass
ruby -c lib/soul_core/music_revision_draft_service.rb: pass
git diff --check: pass
```

## Local LLM evaluation

Not run. Deterministic fixtures validate the local revision request and returned
packet boundary. Musical effectiveness remains a human listening judgment.

## Memory and lifecycle

```text
Memory keys added: none
complete: valid project creation
awaiting_input: invalid mode-specific prompt placement
blocked_for_human_review: unchanged generation and revision gates
failed: unchanged terminal generation failure
```

## Risk and boundaries

Risk is low. The change broadens one bounded text-validation rule for
instrumental captions without adding a runtime field, weakening confirmation,
or changing the trained no-vocal input. It adds no service, listener, queue,
watcher, retry loop, or background process.

## Human review checklist

```text
[ ] Switching to Instrumental disables and clears the lyrics editor.
[ ] The guidance explains that instrumental timing belongs in Sound and Structure.
[ ] A timed instrumental project creates successfully.
[ ] Its exact preview still shows [Instrumental] as the runtime lyrics input.
[ ] A timed vocal caption still asks for timing in the lyrics script.
[ ] Soul-drafted instrumental revisions may retain useful movement timing.
```
