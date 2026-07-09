
# Repository Curation Status

Status: complete for phases 20-22

Date: 2026-07-09

## Summary

The repository hygiene and curation pass established the rules for public documentation, engineering documentation, overlay notes, generated artifacts, runtime state, and durable verifiers.

The phase 22 post-check reached the intended clean state:

```text
tracked_overlay_notes: 0
untracked_review_candidates: 0
untracked_generated_local: 0
repo hygiene verification: complete
```

## Completed work

### Phase 20

Repository hygiene policy was added.

Key outcomes:

```text
.gitignore updated
public vs engineering vs local-only documentation rules documented
generated proposal and runtime paths ignored
overlay note policy documented
hygiene verifier added
```

### Phase 21

Read-only repo curation assessment was added.

Key outcomes:

```text
repo-curation assessment added
repository map added
tracked overlay notes identified
untracked durable verifiers identified
generated local leftovers reported
```

### Phase 22

Explicit curation decisions were recorded and applied.

Key outcomes:

```text
tracked overlay repair notes removed
durable verifiers kept
curation decision log added
curation verifier added
post-check returned clean curation state
```

## Current policy state

### Commit by default

```text
lib/soul_core/*.rb
bin/*
scripts/verify-*.rb
docs/assessments/*.md
docs/workflows/*.md
docs/skills/*.md
docs/soul/*.md
docs/maintenance/*.md
docs/REPOSITORY_HYGIENE.md
docs/REPOSITORY_MAP.md
docs/internal-vs-public.md
```

### Keep local or ignored by default

```text
.env
.env.*
Soul/runtime/*.json
Soul/runtime/*.tmp
Soul/runtime/*.log
Soul/improvement/proposals/*
Soul/artifacts/cloud_assist/*
Soul/proposals/skills/*
overlay_files/
README_*PHASE*.md
README_*REPAIR*.md
docs/overlays/README_*PHASE*.md
docs/overlays/README_*REPAIR*.md
scripts/patch-*.rb
scripts/repair-*.rb
*.zip
```

## Verification commands

```bash
ruby bin/soul assess repo-curation
ruby bin/soul assess repo-curation --json
ruby scripts/verify-repo-hygiene-phase20.rb
ruby scripts/verify-repo-curation-phase21.rb
ruby scripts/verify-repo-curation-decisions-phase22.rb
ruby scripts/verify-repo-curation-summary-phase23.rb
```

## Expected clean state

```text
repo-curation tracked_overlay_notes: 0
repo-curation untracked_review_candidates: 0
repo-curation untracked_generated_local: 0
repo-hygiene verification complete
curation summary verification complete
```

## Future curation

Future repo curation should remain explicit and small.

Do not use:

```bash
git add .
```

Do use:

```bash
git add <explicit paths>
git rm <explicit paths>
```

Generated artifacts should become public only after human review and intentional promotion.
