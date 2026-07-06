# Soul/

Soul/ is a local assistant substrate built around a small local LLM runtime, deterministic skills, verification gates, and human-approved memory/rule promotion.

The model is not treated as the whole assistant. The model is the language organ. Soul/ is the operating layer around it.

## Current status

Soul/ is early experimental software.

Current working pieces:

- local llama.cpp/OpenAI-compatible runtime support
- Ruby CLI
- FAST and THINK request modes
- read-only system status skill
- Downloads cleanup inspection and planning
- top-level Downloads file/folder cleanup candidates
- approval-gated move-to-Trash execution
- Trash treated as terminal cleanup completion
- reflection candidate staging
- reflection approval/rejection workflow
- early natural-language `do` command
- early conversational `respond` command
- deterministic-first, LLM-assisted intent routing

Current primary workflow:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
ruby bin/soul respond "move all except F1"
ruby bin/soul respond "yeah, do it"
```

## Design principles

- No green lights without gauges.
- Skills are preferred over improvisation.
- Read-only planning comes before write actions.
- Trash is the terminal cleanup action for early cleanup workflows.
- Permanent deletion is not supported.
- LLM output is advisory unless validated by deterministic code.
- Durable memory/rule/skill changes are staged and human-reviewed before promotion.
- Public interface should be human-friendly; internal execution should be boring, structured, and safe.

## Development pattern

Soul/ uses overlay-based development.

An overlay is a zip containing a focused set of files to apply to the existing project tree. This keeps changes reviewable and avoids giant unexplained rewrites.

See:

```text
docs/OVERLAY_SYSTEM.md
```

## Local runtime

The expected local runtime for current development is:

```text
http://127.0.0.1:8082/v1
```

Current model alias:

```text
soul-qwen3-8b-q4
```

See:

```text
docs/LOCAL_RUNTIME.md
```

## Repository status

This repository is public for project tracking and transparency.

No open-source license has been selected yet. See `docs/LICENSING.md`.
