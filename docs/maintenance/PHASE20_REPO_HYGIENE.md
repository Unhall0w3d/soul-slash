
# Phase 20 Repo Hygiene

Phase 20 establishes repository hygiene rules after the assessment, alpha, review, and promotion-gate phases.

## Changes

```text
.gitignore
docs/REPOSITORY_HYGIENE.md
docs/assessments/README.md
docs/overlays/README.md
docs/workflows/README.md
docs/internal-vs-public.md
docs/maintenance/PHASE20_REPO_HYGIENE.md
scripts/verify-repo-hygiene-phase20.rb
```

## Policy

- Commit source code and durable verifiers.
- Commit assessment and workflow docs that describe implemented behavior.
- Ignore generated proposals, alpha artifacts, runtime JSON, overlay extraction folders, and generated overlay README notes.
- Keep public-facing docs clean.
- Keep engineering docs useful.
- Treat generated artifacts as local until deliberately promoted.

## Out of scope

Phase 20 does not delete old local debris.

Phase 20 does not resolve whether old untracked phase 9/10 local files should be committed, rewritten, or removed.

That belongs in a later curation pass.
