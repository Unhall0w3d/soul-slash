# Public Repository Hygiene

This document describes public-facing cleanup expectations for Soul/.

## Goals

- Keep local runtime state out of git.
- Keep local model files out of git.
- Keep generated logs and workflow sessions out of git.
- Keep root-level repository docs focused and uncluttered.
- Keep internal overlay notes under `docs/overlays/` when they are worth preserving.
- Avoid exposing local paths, personal environment assumptions, secrets, tokens, model files, or generated state.

## Files that should not be committed

Examples:

```text
.env
.env.*
logs/
run/
tmp/
models/
*.gguf
*.safetensors
*.bin
Soul/logs/tasks/*.json
Soul/logs/tool_runs/*.json
Soul/workflows/pending/*.json
Soul/workflows/sessions/*.json
Soul/reflection/pending/*.json
Soul/reflection/approved/*.json
Soul/reflection/rejected/*.json
```

## Root-level overlay readmes

Generated overlay README files should not accumulate in the repository root.

Preferred locations:

```text
docs/overlays/
docs/overlays/archive/
```

## Branding notes

Branding assets may remain in `assets/brand/` if they are used by the README or repository presentation.

Internal branding notes do not need to be linked from the README. If the repo is meant to present the project rather than the design process, keep that material out of the public landing page.

## Local verification

Run:

```bash
git status --short
git ls-files | grep -E '(^\.env|\.gguf$|\.safetensors$|\.bin$|^logs/|^run/|^tmp/|^models/)'
git check-ignore -v .env models/example.gguf logs/example.log run/example.tmp tmp/example.tmp
git check-ignore -v Soul/logs/tasks/example.json Soul/workflows/sessions/example.json Soul/reflection/pending/example.json
```

The `git ls-files` command should return nothing for ignored local artifacts.

If ignored files were already committed, `.gitignore` will not untrack them automatically. Remove them from the index with:

```bash
git rm --cached <path>
```
