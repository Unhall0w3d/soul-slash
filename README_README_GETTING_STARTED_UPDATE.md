# Soul/ README + Getting Started Overlay

This is the third public setup overlay.

It updates the top-level README and setup docs so they match the new public Makefile/runtime setup flow.

## What it updates

```text
README.md
docs/GETTING_STARTED.md
docs/RUNTIME_PROVIDERS.md
docs/overlays/README_README_GETTING_STARTED_UPDATE.md
README_README_GETTING_STARTED_UPDATE.md
```

## Intent

The README now presents Soul/ as a public project that can be cloned and set up with:

```bash
make check
make detect
make setup
make test-runtime
make test-soul
```

It also explains:

- llama.cpp support
- Ollama support
- GGUF versus Ollama model-name setup differences
- cleanup and restore workflows
- runtime test targets
- project status
- design principles
- branding
- repository license status

## Install

From the repo root:

```bash
unzip ~/Downloads/soul_readme_getting_started_overlay.zip
```

## Review

```bash
git diff -- README.md docs/GETTING_STARTED.md docs/RUNTIME_PROVIDERS.md
```

## Suggested test

```bash
make check
make detect
make env-show
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Update README for public setup flow"
git push origin main
```
