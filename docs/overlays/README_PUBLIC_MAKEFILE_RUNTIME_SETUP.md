# Soul/ Public Makefile Runtime Setup Overlay

This overlay is step 2 of the public setup cleanup.

It replaces the machine-specific Makefile with a generic dispatcher and adds runtime setup/detection/test scripts.

## What it adds or replaces

```text
Makefile
scripts/soul-common.sh
scripts/soul-runtime-detect.sh
scripts/soul-setup-llamacpp.sh
scripts/soul-setup-ollama.sh
scripts/soul-runtime-test.sh
scripts/soul-start-llamacpp.sh
scripts/soul-env-show.sh
docs/overlays/README_PUBLIC_MAKEFILE_RUNTIME_SETUP.md
```

## Design

The Makefile no longer assumes:

- a specific user home directory
- an operator-specific absolute home path
- `/usr/local/bin/llama-server`
- NVIDIA-only hardware
- a systemd user service
- a global model directory outside the repo

Local runtime choices are written to `.env`.

## Runtime support

Soul/ supports both providers at the OpenAI-compatible API layer:

- llama.cpp server
- Ollama

The setup scripts keep model acquisition honest:

- llama.cpp setup downloads and validates Hugging Face GGUF files.
- Ollama setup uses `ollama pull` and Ollama model names.

## Install

From the repo root:

```bash
unzip ~/Downloads/soul_public_makefile_runtime_setup_overlay.zip
chmod +x scripts/soul-*.sh
```

## First run

```bash
make help
make check
make setup
make test-runtime
make test-soul
```

## llama.cpp flow

```bash
make setup-llamacpp
make start-llamacpp
```

Then in another terminal:

```bash
make test-runtime
```

## Ollama flow

```bash
make setup-ollama
make test-runtime
```

## Suggested commit

```bash
git status --short
git add .
git commit -m "Add public runtime setup Makefile and scripts"
git push origin main
```
