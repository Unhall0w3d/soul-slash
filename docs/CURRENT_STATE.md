# Current State

Soul/ is an experimental local-first assistant runtime, not only a model frontend. The current implementation shares one conversation, skill, memory, artifact, approval, and policy core across the CLI and foreground dashboard.

## Implemented product surfaces

```text
Chat
Skill Studio
Self Improvement
```

Chat provides persistent multi-turn conversations, local/model-backed responses, skill routing, artifacts, workspace metadata, inbox delivery, initial host status, and explicit refresh.

The browser dashboard has a single personal administrator boundary. First-run `admin` / `soul123` access is restricted to mandatory password replacement; private dashboard data and controls remain locked until that succeeds. Credentials are salted and derived in ignored local runtime storage. Sessions are bounded to seven days and persist across dashboard restarts using owner-only token digests; raw bearer tokens remain in host-only browser cookies. Sign-ups and additional accounts are unavailable.

Skill Studio provides separate Proposal, Beta, and Production inventories. Human Gate 1 may prepare an exact proposal-local incomplete Beta workspace and bounded Codex handoff without invoking a model. A human or explicitly invoked Codex task implements and tests that candidate. Human Gate 2 approves an exact tested Beta revision; a separate preview/digest/exact-confirmation operation may then copy its self-contained Ruby entrypoint and atomically add one new production registry entry. Existing skills are never replaced, and no gate promotes automatically.

Self Improvement provides one lightweight read-only environment snapshot when opened plus explicit foreground environment, package-update, model-runtime, and capability assessments. It may generate advisory improvement proposal packets only after preview, digest revalidation, and exact confirmation. It cannot apply updates or mutate the host.

## Implemented core capabilities

- model-backed multi-turn conversation with persistent chat identity;
- deterministic capability declarations, intent routing, and skill invocation planning;
- bounded host evidence and follow-up routing;
- layered conversation memory with review, export, and forget controls;
- identity, interests, recent-style awareness, and inspectable boundaries;
- shared artifacts, bounded inspection, creation/revision, and inbox delivery;
- preview-first conversation clearing by exact title, selected set, or all active chats, plus exact single-conversation delete-and-forget;
- production skill registry plus isolated Beta candidates and bounded diagnostics;
- conservative self-skilling intake for genuinely unsupported task requests;
- environment, model-runtime, capability, and improvement-proposal assessment;
- portable typed configuration through CLI overrides, process environment, ignored `.env`, and safe defaults.

## Runtime and deployment boundary

The dashboard is dependency-free static HTML/CSS/JavaScript served by a sequential Ruby foreground loopback process:

```bash
ruby bin/soul dashboard
```

The default command does not install a service, bind to the LAN, poll in the background, or continue after the process stops. An owner-approved optional local deployment candidate now keeps Soul loopback-bound while two explicit user services provide persistent operation and Caddy-managed HTTPS on one exact LAN address. Installation remains preview-first and opt-in; client CA trust and local service behavior require human review. Proxmox, containers, Internet exposure, backups, and recovery remain separate deployment tracks.

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

The Conversational Soul milestone has completed human review of the Phase 12E unified Review Center, Phase 12D.4 proposal lifecycle closeout, Phase 12C.1 seven-day personal authentication, conversation-management amendments, dedicated Skill Studio artwork, and the protected local systemd/Caddy LAN deployment. Phase 12D.5 is now a candidate with bounded Beta workspace preparation and preview-gated Beta-to-production promotion. Phase 13 remains the integrated conversational acceptance and closeout point after human review.

Detailed references:

- `docs/CONVERSATIONAL_SOUL_ROADMAP.md`
- `docs/MILESTONES.md`
- `docs/ARCHITECTURE.md`
- `docs/INTERACTION_ARCHITECTURE.md`
- `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`
- `docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`
- `docs/soul/PHASE12E_UNIFIED_REVIEW_CENTER_BRIEF.md`
- `docs/soul/HUMAN_REVIEW_GATE.md`
