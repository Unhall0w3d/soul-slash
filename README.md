![Soul/ repository header: local-first intelligence substrate, verified actions, recoverable workflows, and human-approved memory](assets/brand/soul-slash-repo-header.png)

# Soul/

**Soul/**, also tracked as **soul-slash** or **Soul Slash**, is a local-first intelligence project for building a trustworthy assistant around local models, deterministic skills, safety gates, recoverable workflows, artifacts, and human-approved memory.

The model is not treated as the whole assistant. The model is the language organ. Soul/ is the operating layer around it.

Soul/ is early experimental software. It is being built in layers so behavior can be inspected, tested, corrected, and approved before it becomes durable.

## Current state

Soul/ currently has:

- terminal chat and persistent chat sessions
- deterministic intent routing and skill planning
- an execution adapter registry
- read-only and review-only execution gates
- local execution history and history controls
- runtime-only approval tokens
- explicit approve, revoke, dry-run, and confirmation flows
- an approval-gated Downloads move-to-trash workflow
- reflection and human-reviewed memory promotion
- bounded cloud-assisted skill proposal tooling
- a controlled Codex handoff and review path that does not mutate production automatically

The completed milestone chain is:

```text
Foundation: complete
Chat and planning: complete
Usability foundation: complete
Safe local action: complete
```

The next milestone is:

```text
Conversational Soul
```

That milestone will turn the current command-oriented chat foundation into a coherent multi-turn conversational runtime that can retain context, invoke skills during discussion, interpret results, create artifacts, and return naturally to the conversation.

## What Soul/ is becoming

Soul/ is intended to grow into a local assistant environment with:

- natural multi-turn conversation
- local model runtime support through an OpenAI-compatible endpoint
- deterministic skills for actions that should not be left to model improvisation
- orchestration that can mix discussion, clarification, tool use, and artifact creation
- layered working, project, semantic, episodic, and preference memory
- safety gates separating planning, approval, execution, and verification
- recoverable operations where early destructive-looking actions use Trash instead
- human-approved durable memory, rules, and skill changes
- optional cloud-assisted research and drafting with explicit privacy boundaries
- future chat, inbox, file-space, dashboard, and voice surfaces using the same assistant core

## Design principles

- No green lights without gauges.
- Conversation is not a decorative wrapper around a command parser.
- Skills are preferred over improvisation when accuracy, state, privacy, or auditability matters.
- LLM output is advisory unless validated by deterministic code.
- Read-only planning comes before write actions.
- Write-capable workflows require explicit user confirmation.
- Trash is the terminal cleanup action for early cleanup workflows.
- Permanent deletion is not supported.
- Cloud output is a review artifact unless a bounded workflow says otherwise.
- Durable memory, rules, and skill updates are staged and human-reviewed before promotion.
- The assistant should explain useful results rather than dumping raw tool output into conversation.
- Humor and personality should arise from context, not quotas or canned phrase rotation.

## Architecture shape

```text
human utterance
-> conversation/session context
-> relevant memory retrieval
-> intent and task interpretation
-> response and tool-use planning
-> direct response, clarification, skill execution, or artifact generation
-> skill-result interpretation
-> conversational response
-> session and candidate-memory update
-> optional human-approved durable promotion
```

Deterministic action workflows retain their stricter boundary:

```text
plan
-> review
-> explicit approval
-> execute
-> verify
-> record
```

See:

```text
docs/ARCHITECTURE.md
docs/INTERACTION_ARCHITECTURE.md
docs/MILESTONES.md
docs/USABILITY_MILESTONE_CLOSEOUT.md
```

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

Soul/ is currently Linux-first.

See:

```text
docs/REQUIREMENTS.md
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

See:

```text
docs/GETTING_STARTED.md
docs/RUNTIME_PROVIDERS.md
```

## Common commands

Start terminal chat:

```bash
ruby bin/soul chat
```

Send a single chat message:

```bash
ruby bin/soul chat "clean up downloads"
```

List available skills:

```bash
ruby bin/soul skills
```

Check project/runtime health:

```bash
ruby bin/soul doctor
ruby bin/soul skill system.status
```

Classify a request:

```bash
ruby bin/soul intent "run a file cleanup in Downloads"
```

Run a legacy workflow:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
ruby bin/soul respond "move all"
ruby bin/soul respond "yeah, do it"
```

Stage and review reflection:

```bash
ruby bin/soul reflect last
ruby bin/soul reflection show latest
ruby bin/soul reflection approve latest --note "Approved after review"
```

For skill-specific commands, see:

```text
docs/SKILLS.md
docs/skills/
```

## Cloud-assisted skill proposal flow

Soul/ can use configured cloud providers to draft and review bounded skill proposal artifacts.

Cloud output remains review-only by default. Codex remains outside automatic production mutation while the project is undergoing broad architectural development.

See:

```text
docs/skills/SKILL_BRIEF_DRAFT.md
docs/skills/SKILL_BRIEF_REVIEW.md
docs/soul/CLOUD_LLM_POLICY.md
docs/soul/SKILL_PROPOSAL_FORMAT.md
docs/CODEX_HANDOFF_CONTRACT.md
```

## Development pattern

Soul/ uses overlay-based development.

An overlay is a focused ZIP containing a small set of files to apply to the existing project tree. This keeps changes reviewable and avoids giant unexplained rewrites.

See:

```text
docs/OVERLAY_SYSTEM.md
docs/overlays/
docs/overlays/archive/
```

## Roadmap direction

Current milestone:

```text
Conversational Soul
```

Planned focus:

- conversational architecture and acceptance contract
- model-backed multi-turn conversation
- conversation-aware tool orchestration
- layered memory and project continuity
- context-sensitive personality and variation
- artifact-aware conversation
- chat, inbox, file-space, and dashboard design
- integrated conversational acceptance testing

Later milestones may cover:

- broader skills and providers
- HTTP API and optional web UI
- voice input, TTS, and wake-word interaction
- deployment, backup, and restore
- broader project-aware and document-aware skills

See:

```text
docs/MILESTONES.md
```

## Repository status

This repository is public for project tracking and transparency.

No open-source license has been selected yet. Public visibility does not automatically grant reuse, modification, or redistribution rights.

See:

```text
docs/LICENSING.md
```
