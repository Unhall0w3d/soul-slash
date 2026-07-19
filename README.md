![Soul/ repository header: a local machine familiar for conversation, capability, creation, and stewardship](assets/brand/soul-slash-repo-header.png)

# Soul/

**Soul/**—also tracked as **soul-slash** or **Soul Slash**—is a local-first machine familiar built around local models, deterministic skills, persistent conversation, creative studios, inspectable memory, explicit authority, and recoverable workflows.

The model is not treated as the whole assistant. It supplies language and reasoning; Soul supplies continuity, capability boundaries, artifacts, orchestration, review gates, and a stable interface across models.

Soul/ is experimental Linux-first software. It is developed in reviewable slices so new behavior can be inspected, tested, corrected, and explicitly accepted before it becomes durable or production-capable.

## What exists now

The authenticated dashboard provides:

- **Chat** — persistent transmissions, immediate message rendering, local-model responses, bounded skill routing, memory, artifacts, workspace, inbox, system status, model runtime controls, and manual Core switching;
- **Self Improvement** — Skill Studio, Self Assessment, and Self Augmentation behind one navigation group;
- **Creative Studios** — Music Studio and Visual Studio with local generation, evidence, revision, lineage, and export flows;
- **Review Center** — redacted pending-approval and recent bounded-execution evidence without granting approval authority.

The supported local runtime topology currently includes:

- **Daily Core** — Gemma 4 12B Instruct Q4_K_M through Ollama/Vulkan on AMD;
- **AMD-Free Core** — Qwen3 8B Q4_K_M through llama.cpp/CUDA on NVIDIA, leaving AMD available;
- **Music Core** — Qwen handles chat on NVIDIA while the bounded ACE-Step Vulkan music runtime uses AMD on demand.

The dashboard can run in the foreground for development or as an explicitly installed local user service. Optional Caddy-based HTTPS exposes one reviewed LAN endpoint while Soul itself remains loopback-bound.

Music Studio currently supports 30-, 90-, and 180-second projects, FLAC/MP3 candidates, persistent generation jobs, vocal evidence, revision lineage, lawful reference profiles, static visual companions, finished-song export, and exact local YouTube upload packages. Visual Studio provides bounded local still generation, review, guided edits, deletion, and exact binding to Music candidates. Upload and publication remain human actions.

For a concise implementation and boundary map, see [Current State](docs/CURRENT_STATE.md).

## Use the dashboard

These guides explain the product surfaces, intended workflows, and human gates:

| Surface | Purpose | Guide |
| --- | --- | --- |
| Skill Studio | Move a bounded capability from proposal through Beta evidence to explicit production promotion | [Skill Studio](docs/guides/SKILL_STUDIO.md) |
| Self Assessment | Inspect host, runtime, capability, update, and storage evidence without mutating the machine | [Self Assessment](docs/guides/SELF_ASSESSMENT.md) |
| Self Augmentation | Prepare isolated architecture-level experiments when a skill is not sufficient | [Self Augmentation](docs/guides/SELF_AUGMENTATION.md) |
| Music Studio | Create, analyze, revise, review, finish, and package local compositions | [Music Studio](docs/guides/MUSIC_STUDIO.md) |
| Visual Studio | Generate, review, revise, and bind private local still imagery | [Visual Studio](docs/guides/VISUAL_STUDIO.md) |

## Design principles

- No green lights without gauges.
- Conversation is not a decorative wrapper around a command parser.
- Skills are preferred over improvisation when accuracy, state, privacy, or auditability matters.
- Model output is advisory unless deterministic code validates it.
- Read-only planning precedes write actions.
- Risky, destructive, privileged, durable, or production-changing operations require explicit human authority.
- Trash remains preferred for early filesystem cleanup; permanent deletion is limited to exact previewed scopes such as conversations and private studio projects.
- Passing tests is evidence, not approval.
- Cloud output remains a candidate artifact unless a reviewed workflow says otherwise.
- Durable memory, rules, skills, and core changes are staged and reviewed before promotion.
- Personality should feel present without obscuring truthful state, limitations, or provenance.

## Architecture

The conversational path is:

```text
human message
→ conversation and relevant memory
→ intent, capability, and policy interpretation
→ response, clarification, skill, research, or artifact plan
→ bounded execution when needed
→ evidence-aware response
→ session update
→ optional human-reviewed durable promotion
```

State-changing workflows retain a stricter boundary:

```text
plan
→ preview exact scope
→ explicit approval
→ execute within bounds
→ verify
→ record evidence
```

Creative workflows add candidate lineage rather than overwriting their source:

```text
brief
→ exact generation
→ candidate
→ machine evidence where useful
→ human review
→ keep, revise, reject, bind, or export
```

See [Architecture](docs/ARCHITECTURE.md), [Interaction Architecture](docs/INTERACTION_ARCHITECTURE.md), and [Milestones](docs/MILESTONES.md).

## Requirements

Required for the base project:

- Ruby
- Git
- Make
- curl
- unzip
- an OpenAI-compatible local runtime through llama.cpp or Ollama

Recommended:

- jq and zip
- Python 3
- a supported GPU runtime
- Caddy for the optional protected LAN deployment

Music and visual tooling is optional, hardware-dependent, separately planned, and never installed by the base setup without its own confirmation gates. See [Getting Started](docs/GETTING_STARTED.md).

## Quick start

```bash
git clone https://github.com/Unhall0w3d/soul-slash.git
cd soul-slash
make check
make detect
make setup
make test-runtime
make test-soul
make dashboard
```

Open `http://127.0.0.1:4567/`.

First-run access uses username `admin` and bootstrap password `soul123`. The bootstrap session cannot load private dashboard data; Soul requires a replacement password of 12–128 characters before entry. Sign-ups and additional accounts are unavailable.

If the local administrator password is lost, stop the dashboard and run:

```bash
make dashboard-reset-admin
```

This revokes active sessions and restores the mandatory password-change gate.

For a persistent local dashboard and protected LAN access, follow the preview-first service and Caddy instructions in [Local systemd and HTTPS deployment](docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md). No service, listener, firewall rule, certificate trust, or LAN exposure is installed automatically after clone.

## Common commands

```bash
# Terminal conversation
ruby bin/soul chat
ruby bin/soul chat "inspect this machine"

# Capability and health inventory
ruby bin/soul skills
ruby bin/soul doctor
ruby bin/soul skill system.status

# Bounded assessments
ruby bin/soul assess environment
ruby bin/soul assess environment --updates
ruby bin/soul assess models
ruby bin/soul assess capabilities

# Dashboard
make dashboard
make dashboard-service-status

# Configuration
make env-show
make test-runtime
make test-soul
```

Configuration precedence is:

```text
CLI override
→ process environment
→ ignored local .env
→ tracked safe default
```

The public repository must not contain operator-specific credentials, addresses, hostnames, model paths, private memory, or generated project data.

## Skills, augmentation, and cloud assistance

Production skills are deterministic bounded capabilities. Beta candidates remain isolated and Operator-invoked until exact tested promotion. Self Augmentation is a separate lane for core architecture changes and cannot merge or deploy its own candidates.

Optional cloud providers may help draft, synthesize, or critique review artifacts. Cloud output cannot decide safety, authority, memory promotion, production promotion, or merge readiness, and it must not receive secrets or private memory.

See:

- [Skills](docs/SKILLS.md)
- [Cloud LLM policy](docs/soul/CLOUD_LLM_POLICY.md)
- [Human review gate](docs/soul/HUMAN_REVIEW_GATE.md)
- [Codex handoff contract](docs/CODEX_HANDOFF_CONTRACT.md)

## Development and historical evidence

Current work uses reviewed branches, deterministic verifiers, human review artifacts, and bounded implementation briefs. The repository also retains historical phase, overlay, and assessment documents as engineering evidence. Those records describe how Soul arrived here; the README, current-state map, architecture, and operator guides describe how it works now.

See [Repository Map](docs/REPOSITORY_MAP.md) and [Roadmap](docs/ROADMAP.md).

## Repository status

This repository is public for project tracking and transparency.

No open-source license has been selected. Public visibility does not automatically grant reuse, modification, or redistribution rights. See [Licensing](docs/LICENSING.md).
