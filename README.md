<p align="center">
  <img src="assets/brand/soul-slash-repo-header.png" alt="Soul/ repository header: local-first intelligence substrate, verified actions, recoverable workflows, and human-approved memory">
</p>

# Soul/

**Soul/**, also tracked as **soul-slash** or **Soul Slash**, is a local intelligence project for building a trustworthy assistant layer around small local models, deterministic skills, safety gates, recoverable workflows, and human-approved memory.

The model is not treated as the whole assistant. The model is the language organ. **Soul/** is the operating layer around it.

Soul/ is being built as a local-first assistant substrate that can understand human requests, select known workflows, run verified skills, ask before taking write actions, recover from approved cleanup actions, and preserve useful lessons only after human review.

## Current status

Soul/ is early experimental software.

Current working pieces include:

- Ruby CLI
- local OpenAI-compatible runtime support
- llama.cpp server runtime setup support
- Ollama runtime setup support
- FAST and THINK request modes
- read-only system status skill
- Downloads cleanup inspection and planning
- top-level Downloads file/folder cleanup candidates
- approval-gated move-to-Trash execution
- Trash treated as terminal cleanup completion
- restore-last-cleanup rollback workflow
- reflection candidate staging
- reflection approval/rejection workflow
- early natural-language `do` command
- early conversational `respond` command
- deterministic-first, LLM-assisted intent routing

This is not a finished assistant. It is a project being built in layers so behavior can be inspected, tested, corrected, and approved before it becomes durable.

## What Soul/ is becoming

Soul/ is intended to grow into a local assistant environment with:

- **Local model runtime support** for small local LLMs exposed through an OpenAI-compatible endpoint.
- **Human-accessible interaction** through natural-language CLI now, with future voice, TTS, and UI layers.
- **Deterministic skills** for real actions that should not be left to improvisation.
- **Workflow orchestration** that turns human requests into known, validated skill sequences.
- **Safety gates** that separate planning, selection, confirmation, execution, and verification.
- **Recoverable operations** where cleanup actions move to Trash first and can be restored.
- **Human-approved memory** where durable lessons and operating rules are staged, reviewed, and approved before promotion.
- **Overlay-based development** for small, reviewable feature increments while the project is still evolving quickly.

## Design principles

- **No green lights without gauges.**
- Skills are preferred over improvisation.
- LLM output is advisory unless validated by deterministic code.
- Read-only planning comes before write actions.
- Write-capable workflows require explicit user confirmation.
- Trash is the terminal cleanup action for early cleanup workflows.
- Permanent deletion is not supported.
- Recovery should be designed into workflows, not treated as an afterthought.
- Durable memory, rules, and skill updates are staged and human-reviewed before promotion.
- The public interface should be human-friendly; the internal execution path should be boring, structured, and safe.

## Architecture shape

```text
human request
  -> intent routing
  -> workflow selection
  -> skill planning
  -> human review / selection
  -> explicit confirmation
  -> deterministic execution
  -> verification
  -> optional restore
  -> optional reflection
  -> human-approved memory/rule promotion
```

The long-term goal is not a chatbot that guesses commands. The goal is a local operating layer that can translate human intent into verified, recoverable, approval-gated workflows.

## Requirements

Required:

- Ruby
- Git
- Make
- curl
- unzip
- either llama.cpp server or Ollama

Recommended:

- jq
- zip
- Python 3
- a GPU-supported local model runtime, if available

Soul/ is currently Linux-first. The CLI and runtime-provider model are intended to become more portable, but the active cleanup/restore workflows currently assume Linux-style filesystem and Trash behavior.

See:

```text
docs/REQUIREMENTS.md
```

## Runtime providers

Soul/ can use either:

- **llama.cpp server**
- **Ollama**

Both are supported at the OpenAI-compatible API layer.

The setup flows are intentionally different:

| Provider | Model setup | Default API |
|---|---|---|
| llama.cpp | GGUF file, often downloaded from Hugging Face | `http://127.0.0.1:8082/v1` |
| Ollama | Ollama model name via `ollama pull` | `http://127.0.0.1:11434/v1` |

Tested llama.cpp default:

```text
Qwen3-8B-Q4_K_M.gguf
soul-qwen3-8b-q4
```

Example Ollama model:

```text
qwen3:8b
```

Soul/ does not package or host llama.cpp, Ollama, or model files.

See:

```text
docs/RUNTIME_PROVIDERS.md
```

## Quick start

Clone the repository:

```bash
git clone https://github.com/Unhall0w3d/soul-slash.git
cd soul-slash
```

Check local tools:

```bash
make check
```

Detect installed runtimes, reachable endpoints, current `.env`, and local GGUF models:

```bash
make detect
```

Run guided setup:

```bash
make setup
```

Or choose a provider directly:

```bash
make setup-llamacpp
```

```bash
make setup-ollama
```

Show the selected local configuration:

```bash
make env-show
```

Test the configured runtime:

```bash
make test-runtime
```

Run basic Soul/ checks:

```bash
make test-soul
```

See the full getting started guide:

```text
docs/GETTING_STARTED.md
```

## llama.cpp setup path

Use llama.cpp if you want direct control over GGUF files and runtime flags.

```bash
make setup-llamacpp
```

The setup script will:

- detect or ask for `llama-server`
- ask for a model alias
- search for local GGUF files in `./models` and `~/Downloads`
- offer to use an existing detected GGUF file
- otherwise ask for a Hugging Face GGUF URL
- download the model into `./models` by default
- validate GGUF magic bytes
- write `.env`

Start llama.cpp in the foreground:

```bash
make start-llamacpp
```

Then, in another terminal:

```bash
make test-runtime
```

## Ollama setup path

Use Ollama if you want a simpler local model manager.

```bash
make setup-ollama
```

The setup script will:

- detect `ollama`
- ask for an Ollama model name
- check whether the model is already installed
- run `ollama pull` only if needed
- check the OpenAI-compatible endpoint
- write `.env`

Then run:

```bash
make test-runtime
```

## Common commands

List available skills:

```bash
ruby bin/soul skills
```

Check project/runtime health:

```bash
ruby bin/soul doctor
ruby bin/soul skill system.status
```

Classify a natural-language request:

```bash
ruby bin/soul intent "run a file cleanup in Downloads"
ruby bin/soul intent "restore the last downloads cleanup"
```

Run a Downloads cleanup workflow:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
ruby bin/soul respond "move all"
ruby bin/soul respond "yeah, do it"
```

Restore the last successful Downloads cleanup:

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

Stage and review reflection:

```bash
ruby bin/soul reflect last
ruby bin/soul reflection show latest
ruby bin/soul reflection approve latest --note "Approved after review"
ruby bin/soul reflection reject latest --reason "Not useful"
```

## Cleanup workflow example

Create harmless test fixtures:

```bash
mkdir -p ~/Downloads/restore-fixture-folder
touch ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-folder
```

Run cleanup:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 3 days"
ruby bin/soul respond "move all"
ruby bin/soul respond "yeah, do it"
```

Run restore:

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

Verify:

```bash
ls -la ~/Downloads | grep restore-fixture
```

Clean up the fixtures:

```bash
rm -rf ~/Downloads/restore-fixture-file.tmp ~/Downloads/restore-fixture-folder
```

## Make targets

```text
make help             Show available targets
make check            Check required/recommended local tools only
make detect           Detect runtimes, endpoints, config, and local GGUF models
make setup            Guided runtime setup
make setup-llamacpp   Configure llama.cpp provider
make setup-ollama     Configure Ollama provider
make test-runtime     Test configured runtime
make test-fast        Test FAST/no_think request mode
make test-think       Test THINK request mode
make test-soul        Run basic Soul/ CLI checks
make doctor           Run Soul/ doctor
make env-show         Show local runtime config
make fix-mtimes       Touch repo files if ZIP timestamps caused Make clock-skew warnings
```

## Development pattern

Soul/ uses overlay-based development.

An overlay is a zip containing a focused set of files to apply to the existing project tree. This keeps changes reviewable and avoids large unexplained rewrites.

See:

```text
docs/OVERLAY_SYSTEM.md
```

## Roadmap direction

Near-term:

- strengthen Downloads cleanup and restore regression testing
- improve workflow/session listing and pruning
- improve voice-friendly response rendering
- load approved memory/rules into prompts safely
- expand skill registry validation
- continue packaging changes as focused overlays

Later:

- web UI shell
- voice input and TTS output
- wake-word integration
- project-aware skills
- local document search
- optional vector memory
- broader workflow domains beyond Downloads cleanup

## Repository status

This repository is public for project tracking and transparency.

No open-source license has been selected yet. Public visibility does not automatically grant reuse, modification, or redistribution rights.

See:

```text
docs/LICENSING.md
```
