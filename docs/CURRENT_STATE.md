# Current State

Soul/ is an experimental local-first assistant runtime, not only a model frontend. The current implementation shares one conversation, skill, memory, artifact, approval, and policy core across the CLI and foreground dashboard.

## Implemented product surfaces

```text
Chat
Skill Studio
Self Improvement
```

Chat provides persistent multi-turn conversations, local/model-backed responses, skill routing, artifacts, workspace metadata, inbox delivery, initial host status, and explicit refresh.

Skill Studio provides separate Proposal, Beta, and Production inventories. Human Gate 1 approves an exact proposal revision for Beta implementation work. Human Gate 2 approves an exact tested Beta revision for a later promotion workflow. Neither gate implements, registers, promotes, merges, or releases automatically.

Self Improvement provides one lightweight read-only environment snapshot when opened plus explicit foreground environment, package-update, model-runtime, and capability assessments. It may generate advisory improvement proposal packets only after preview, digest revalidation, and exact confirmation. It cannot apply updates or mutate the host.

## Implemented core capabilities

- model-backed multi-turn conversation with persistent chat identity;
- deterministic capability declarations, intent routing, and skill invocation planning;
- bounded host evidence and follow-up routing;
- layered conversation memory with review, export, and forget controls;
- identity, interests, recent-style awareness, and inspectable boundaries;
- shared artifacts, bounded inspection, creation/revision, and inbox delivery;
- preview-first conversation clearing and exact conversation delete-and-forget;
- production skill registry plus isolated Beta candidates and bounded diagnostics;
- conservative self-skilling intake for genuinely unsupported task requests;
- environment, model-runtime, capability, and improvement-proposal assessment;
- portable typed configuration through CLI overrides, process environment, ignored `.env`, and safe defaults.

## Runtime and deployment boundary

The dashboard is dependency-free static HTML/CSS/JavaScript served by a sequential Ruby foreground loopback process:

```bash
ruby bin/soul dashboard
```

It does not install a service, bind to the LAN, poll in the background, or continue after the process stops. Proxmox, containers, persistent services, LAN exposure, backups, and recovery remain a later separately approved deployment track.

## Human authority boundary

Soul may assess, explain, draft, stage, test, and produce review artifacts. It may not treat model output or passing tests as approval.

Human approval remains required for:

- risky or destructive execution;
- durable memory/rule promotion;
- proposal and Beta gates;
- system/package mutation;
- provider/privacy exceptions;
- merge and release decisions;
- persistent-service or deployment architecture.

## Current development position

The Conversational Soul milestone has reached the Phase 12D.3 Self Improvement dashboard. The next planned interface slice is Phase 12E unified approvals and activity views. Phase 13 is the integrated acceptance and closeout point before a separately reviewed deployment phase.

Detailed references:

- `docs/CONVERSATIONAL_SOUL_ROADMAP.md`
- `docs/MILESTONES.md`
- `docs/ARCHITECTURE.md`
- `docs/INTERACTION_ARCHITECTURE.md`
- `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`
- `docs/soul/HUMAN_REVIEW_GATE.md`
