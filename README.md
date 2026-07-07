<p align="center">
  <img src="assets/brand/soul-slash-repo-header.png" alt="Soul/ repository header: local-first intelligence substrate, verified actions, recoverable workflows, and human-approved memory">
</p>

# Soul/

**Soul/**, also tracked as **soul-slash** or **Soul Slash**, is a local intelligence project for building a trustworthy assistant layer around small local models, deterministic skills, safety gates, recoverable workflows, and human-approved memory.

The model is not treated as the whole assistant. The model is the language organ. **Soul/** is the operating layer around it.

Soul/ is being built as a local-first assistant substrate that can understand human requests, select known workflows, run verified skills, ask before taking write actions, recover from approved cleanup actions, and preserve useful lessons only after human review.

## What Soul/ is becoming

Soul/ is intended to grow into a local assistant environment with:

- **Local model runtime support** for small local LLMs exposed through an OpenAI-compatible endpoint.
- **Human-accessible interaction** through natural-language CLI now, with future voice, TTS, and UI layers.
- **Deterministic skills** for real actions that should not be left to improvisation.
- **Workflow orchestration** that turns messy human requests into known, validated skill sequences.
- **Safety gates** that separate planning, selection, confirmation, execution, and verification.
- **Recoverable operations** where cleanup actions move to Trash first and can be restored.
- **Human-approved memory** where durable lessons and operating rules are staged, reviewed, and approved before promotion.
- **Overlay-based development** for small, reviewable feature increments while the project is still evolving quickly.

This is a project, not a polished product. It is deliberately being built in layers so behavior can be inspected, tested, corrected, and approved before it becomes durable.

## Current status

Soul/ is early experimental software.

Current working pieces include:

- local llama.cpp / OpenAI-compatible runtime support
- Ruby CLI
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

Current primary cleanup workflow:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
ruby bin/soul respond "move all except F1"
ruby bin/soul respond "yeah, do it"
```

Current rollback workflow:

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

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

## Local runtime

The expected local runtime for current development is:

```text
http://127.0.0.1:8082/v1
```

Current model alias:

```text
soul-qwen3-8b-q4
```

Useful checks:

```bash
ruby bin/soul doctor
ruby bin/soul skill system.status
```

More runtime notes live in:

```text
docs/LOCAL_RUNTIME.md
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

## Development pattern

Soul/ uses overlay-based development.

An overlay is a zip containing a focused set of files to apply to the existing project tree. This keeps changes reviewable and avoids giant unexplained rewrites. Yes, we are choosing structure over entropy. Disturbing, but healthy.

See:

```text
docs/OVERLAY_SYSTEM.md
```

## Branding

The current visual direction is **techno-grimoire**: arcane diagrams, spectral light, grimoire/codex imagery, circuit traces, and local AI orchestration motifs.

Brand assets live in:

```text
assets/brand/
```

Primary assets:

- `assets/brand/soul-slash-repo-header.png`
- `assets/brand/soul-slash-brand-board.png`
- `assets/brand/soul-slash-primary-mark.png`
- `assets/brand/soul-slash-repo-icon.png`
- `assets/brand/soul-slash-supporting-scene.png`

Branding notes live in:

```text
docs/branding/BRANDING.md
```

## Roadmap direction

Near-term:

- strengthen the Downloads cleanup and restore regression test harness
- improve workflow/session listing and pruning
- improve voice-friendly response rendering
- load approved memory/rules into prompts safely
- expand the skill registry validation layer
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

No open-source license has been selected yet. Public visibility does not automatically grant reuse, modification, or redistribution rights. See:

```text
docs/LICENSING.md
```
