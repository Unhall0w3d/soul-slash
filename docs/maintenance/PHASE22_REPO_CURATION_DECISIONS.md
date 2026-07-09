
# Phase 22 Repo Curation Decisions

Phase 22 records and verifies explicit curation decisions from the phase 21 assessment.

## Input from phase 21

The phase 21 assessment identified:

```text
tracked_overlay_notes: 3
untracked_review_candidates: 2
untracked_generated_local: 0
```

## Decisions

### Remove tracked overlay notes

```text
docs/overlays/README_WEATHER_REFLECTION_HANDLER_REPAIR.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md
```

These are repair/application notes, not stable public or engineering docs.

### Keep durable verifiers

```text
scripts/verify-alpha-review-phase18.rb
scripts/verify-repo-curation-phase21.rb
```

These are regression verifiers for committed behavior.

## Scope

This phase does not add automatic cleanup behavior.

This phase does not modify source code.

This phase intentionally requires explicit `git rm` and `git add` commands.
