
# Repository Curation Decisions

This log records deliberate repository curation decisions.

The purpose is to avoid broad cleanup commits, accidental `git add .`, and mysterious deletions that future maintainers have to interpret like cave paintings.

## Phase 22 decisions

Date: 2026-07-09

### Tracked overlay notes

Decision: remove from tracking.

Files:

```text
docs/overlays/README_WEATHER_REFLECTION_HANDLER_REPAIR.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md
```

Rationale:

- These are repair/application notes, not stable product documentation.
- The current overlay policy treats generated repair notes as temporary unless rewritten into stable docs.
- Keeping them tracked creates noise in hygiene assessment.
- The underlying implemented behavior should be documented elsewhere if still relevant.

Required action:

```bash
git rm docs/overlays/README_WEATHER_REFLECTION_HANDLER_REPAIR.md \
  docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md \
  docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md
```

### Durable verifiers

Decision: keep and commit.

Files:

```text
scripts/verify-alpha-review-phase18.rb
scripts/verify-repo-curation-phase21.rb
```

Rationale:

- `scripts/verify-alpha-review-phase18.rb` validates committed alpha review behavior.
- `scripts/verify-repo-curation-phase21.rb` validates committed repo curation behavior.
- Project convention treats `verify-*` scripts as durable regression verifiers.

Required action:

```bash
git add scripts/verify-alpha-review-phase18.rb \
  scripts/verify-repo-curation-phase21.rb
```

### Generated local leftovers

Decision: keep ignored, remove when not actively inspecting.

Current curation assessment found no generated/local leftovers requiring action.

If generated leftovers appear again, clean them without staging:

```bash
rm -rf overlay_files
rm -rf Soul/improvement/proposals/*
touch Soul/improvement/proposals/.keep
rm -f Soul/runtime/*.json Soul/runtime/*.tmp Soul/runtime/*.log
touch Soul/runtime/.keep
```

## Standing curation rules

- Do not use `git add .`.
- Remove temporary overlay notes only with explicit paths.
- Commit durable verifiers explicitly.
- Rewrite useful overlay history into stable docs before committing.
- Keep generated proposals and alpha artifacts local unless promoted through a future workflow.
