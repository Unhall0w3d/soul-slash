# Soul/ Repository Branding + README Overlay

This overlay adds the selected Soul/ techno-grimoire branding bundle and replaces `README.md` with an updated project-focused README.

## What it adds

```text
assets/brand/soul-slash-brand-board.png
assets/brand/soul-slash-repo-header.png
assets/brand/soul-slash-supporting-scene.png
assets/brand/soul-slash-primary-mark.png
assets/brand/soul-slash-repo-icon.png
docs/branding/BRANDING.md
docs/overlays/README_REPO_BRANDING_README_UPDATE.md
README.md
```

## Intent

The README now describes both the current repository state and the longer-term direction for Soul/:

- local-first intelligence substrate
- deterministic skills
- safety gates
- verified workflows
- recoverable actions
- human-approved memory/rule promotion
- model as language organ, Soul/ as operating layer

## Install

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_repo_branding_readme_overlay.zip
```

## Verify

```bash
git status --short
ls -lh assets/brand/
```

## Suggested commit

```bash
git add .
git commit -m "Add Soul branding assets and update README"
git push origin main
```
