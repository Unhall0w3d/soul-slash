
# Public Repository Hygiene

This document defines what belongs in the public Soul/ repository and what should remain local.

## Goals

- Keep runtime state, model files, local secrets, and generated proposal artifacts out of git.
- Keep public-facing documentation focused on current behavior, architecture, and safety boundaries.
- Keep overlay application notes out of normal history unless they are deliberately curated.
- Keep durable regression verifiers committed so future changes can be checked without reconstructing old overlay context.
- Avoid exposing local paths, personal environment assumptions, secrets, tokens, model files, generated state, or temporary alpha artifacts.

## Commit by default

These files are normally appropriate to commit:

```text
lib/soul_core/*.rb
bin/*
scripts/verify-*.rb
docs/assessments/*.md
docs/workflows/*.md
docs/skills/*.md
docs/soul/*.md
docs/REPOSITORY_HYGIENE.md
docs/OVERLAY_SYSTEM.md
docs/SECURITY_MODEL.md
docs/SKILLS.md
```

`verify-*` scripts are durable regression verifiers. They should stay unless replaced by a newer consolidated verifier.

## Do not commit by default

These files are normally local, generated, temporary, or review-only:

```text
.env
.env.*
Soul/runtime/*.json
Soul/runtime/*.tmp
Soul/runtime/*.log
Soul/improvement/proposals/*
Soul/artifacts/cloud_assist/*
Soul/artifacts/conversation_artifacts.jsonl
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

Generated improvement proposals and alpha artifacts are intentionally local. They are review material, not source code, until a future explicit promotion workflow copies reviewed artifacts into production paths.

## Documentation classes

Soul documentation is divided into three working categories.

### Public product docs

Public product docs describe current user-visible behavior, safety boundaries, setup, or capabilities.

Examples:

```text
README.md
docs/SKILLS.md
docs/SECURITY_MODEL.md
docs/ROADMAP.md
docs/skills/*.md
```

These should be readable without knowing the overlay history.

### Engineering docs

Engineering docs describe implemented architecture, phase outcomes, and verification assumptions.

Examples:

```text
docs/assessments/*.md
docs/workflows/*.md
docs/soul/*.md
```

These may be public, but they do not all need to be linked from the main README.

### Overlay notes

Overlay notes describe how to apply a generated overlay.

Examples:

```text
README_*PHASE*.md
docs/overlays/README_*PHASE*.md
README_*REPAIR*.md
docs/overlays/README_*REPAIR*.md
```

Overlay notes are temporary by default. Curated historical notes may be moved to an archive only when they explain an architectural decision that is still useful.

## Local verification

Run:

```bash
ruby scripts/verify-repo-hygiene-phase20.rb
```

Useful manual checks:

```bash
git status --short
git ls-files | grep -E '(^\.env|\.gguf$|\.safetensors$|\.bin$|^logs/|^run/|^tmp/|^models/)'
git check-ignore -v .env models/example.gguf logs/example.log run/example.tmp tmp/example.tmp
git check-ignore -v Soul/improvement/proposals/example/metadata.json
git check-ignore -v Soul/runtime/capability_matrix.json
git check-ignore -v overlay_files/example.txt
git check-ignore -v README_EXAMPLE_PHASE20.md
git check-ignore -v docs/overlays/README_EXAMPLE_PHASE20.md
```

The `git ls-files` command should return nothing for ignored local artifacts.

## If ignored files were already committed

`.gitignore` does not untrack files that were already committed.

Remove generated files from the index without deleting local copies:

```bash
git rm --cached <path>
```

Use this only after deciding the file is generated/local and should not remain tracked.

## Extracted overlay directories

Tracked directories ending in `_overlay/` are delivery artifacts, not canonical project structure. Before removal, verify duplicate assets against canonical paths and promote any unique durable document into canonical repository structure. The curation assessor reports any tracked extracted overlay directory.
