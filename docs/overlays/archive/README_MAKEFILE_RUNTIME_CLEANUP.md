# Soul/ Makefile Runtime Cleanup Overlay

This overlay cleans up the public runtime Makefile and setup scripts before the README quick-start overlay.

## Fixes

- Separates `make check` from `make detect`.
- Adds `make fix-mtimes` for local clock-skew cleanup.
- Packages files with fixed historical timestamps to avoid Make clock-skew warnings after unzip.
- Expands runtime endpoint probing.
- Adds llama.cpp GGUF model discovery in:
  - `./models`
  - `~/Downloads`
- Avoids redundant llama.cpp setup if `.env` already points to a reachable provider.
- Avoids redundant Ollama pull if the selected model is already installed.
- Keeps `/v1` as the OpenAI-compatible runtime API path.
- Probes Ollama native `/api/tags` separately.

## Target behavior

### make check

Only checks local tools and `.env` presence.

```bash
make check
```

### make detect

Detects runtime binaries, reachable endpoints, current config, and local GGUF models.

```bash
make detect
```

### make setup

Uses detection first, then guides provider setup.

```bash
make setup
```

### make fix-mtimes

If Make still complains about future file modification times after extracting an overlay:

```bash
make fix-mtimes
```

This touches tracked working-tree files to current local time. Primitive? Yes. Effective? Also yes. Civilization is a series of tasteful hacks.

## Install

From the repo root:

```bash
unzip ~/Downloads/soul_makefile_runtime_cleanup_overlay.zip
chmod +x scripts/soul-*.sh
```

## Verify

```bash
make help
make check
make detect
make env-show
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Clean up public runtime Makefile detection and setup"
git push origin main
```
