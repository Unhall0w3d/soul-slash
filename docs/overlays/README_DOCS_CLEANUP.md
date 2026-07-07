# Soul/ Documentation Cleanup Overlay

This overlay performs the README/docs cleanup pass.

The main README becomes a project overview and setup entry point instead of a crowded museum of every skill, workflow, and historical accident we have dragged through the repo.

## Adds / updates

```text
README.md
docs/SKILLS.md
scripts/archive-root-overlay-readmes.rb
scripts/verify-docs-cleanup.rb
```

## Creates

```text
docs/overlays/archive/
```

## What changes

```text
root README_*.md overlay notes move to docs/overlays/archive/
main README links to docs/SKILLS.md instead of carrying all skill details
docs/SKILLS.md becomes the public skill index
detailed usage remains under docs/skills/*.md
.gitignore ignores future root README_*.md overlay files
```

## Why

Root overlay readmes were useful while building quickly, but they do not belong in the public repo root forever. That is how a project root turns into a junk drawer with Git history.

## Apply

```bash
unzip ~/Downloads/soul_docs_cleanup_overlay.zip
chmod +x scripts/archive-root-overlay-readmes.rb scripts/verify-docs-cleanup.rb
ruby scripts/archive-root-overlay-readmes.rb
```

## Verify

```bash
ruby scripts/verify-docs-cleanup.rb
```

Expected:

```text
Verification complete.
```

## Review

```bash
git status --short
git diff -- README.md docs/SKILLS.md .gitignore
find docs/overlays/archive -maxdepth 1 -type f | sort
```

## Commit

```bash
git add README.md docs/SKILLS.md .gitignore docs/overlays/archive scripts/verify-docs-cleanup.rb
git commit -m "Clean up README and skill documentation"
git push origin main
```

## Cleanup script

You may remove the archive script before commit if you do not want to keep it:

```bash
rm scripts/archive-root-overlay-readmes.rb
```

If you remove it, do not include it in `git add`.

Keep the verifier if you want future documentation hygiene checks:

```text
scripts/verify-docs-cleanup.rb
```
