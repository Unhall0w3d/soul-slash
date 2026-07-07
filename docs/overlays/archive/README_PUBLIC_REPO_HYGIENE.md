# Soul/ Public Repository Hygiene Overlay

This overlay updates public-facing repository hygiene.

## What it changes

```text
README.md
.gitignore
.env.example
docs/REPOSITORY_HYGIENE.md
scripts/repo-public-hygiene-cleanup.sh
docs/overlays/README_PUBLIC_REPO_HYGIENE.md
README_PUBLIC_REPO_HYGIENE.md
```

## Why

The repository is public, so the root README should focus on setup, architecture, usage, and project direction. Internal branding rationale does not need to be part of the public landing page.

The overlay also strengthens `.gitignore` for:

- `.env`
- local runtime folders
- logs
- workflow sessions
- reflection drafts/results
- local model files
- generated zip overlays
- temporary backup files

## Apply

```bash
unzip ~/Downloads/soul_public_repo_hygiene_overlay.zip
chmod +x scripts/repo-public-hygiene-cleanup.sh
```

## Run cleanup script

```bash
scripts/repo-public-hygiene-cleanup.sh
```

The script moves root-level generated README artifacts into `docs/overlays/archive/` and removes `docs/branding/`.

It does not remove `assets/brand/`, because the README still uses the header image.

## Verify

```bash
git status --short
git diff -- README.md .gitignore .env.example docs/REPOSITORY_HYGIENE.md
git ls-files | grep -E '(^\.env|\.gguf$|\.safetensors$|\.bin$|^logs/|^run/|^tmp/|^models/)'
git check-ignore -v .env models/example.gguf logs/example.log run/example.tmp tmp/example.tmp
```

The `git ls-files` command should return nothing.

## Suggested commit

```bash
git add .
git commit -m "Clean up public repo hygiene"
git push origin main
```
