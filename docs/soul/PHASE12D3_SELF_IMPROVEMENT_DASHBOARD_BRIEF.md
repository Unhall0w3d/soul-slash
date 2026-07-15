# Phase 12D.3 Approved Brief: Self Improvement Dashboard

```text
brief_status: approved from human direction dated 2026-07-15
implementation_authorized: yes
human_review_required: yes
human_merge_review_required: yes
```

## Purpose

Expose Soul's existing environment, runtime, model, capability, and improvement-proposal loop as a third dashboard tab without turning assessment into unattended administration.

## Bounded flow

```text
open Self Improvement tab
→ collect one lightweight read-only environment snapshot
→ human optionally requests one deeper bounded assessment
→ Soul presents evidence and recommendations
→ human optionally previews improvement-proposal generation
→ human confirms the exact assessed revision
→ Soul writes advisory proposal packets only
→ stop for human review
```

The automatic tab-open snapshot must not check remote package updates, contact cloud providers, persist a capability matrix, generate proposals, install packages, or alter the host.

## Manual assessment scopes

- `environment`: OS, project, package-manager detection, and language/tool versions.
- `updates`: read-only package update, orphan, and unused-runtime checks.
- `models`: local loopback model endpoints, local commands, acceleration hints, and bounded model-file inventory.
- `capabilities`: the current Soul capability matrix, including the implemented Skill Studio Beta lifecycle.

Every assessment runs once in the foreground and terminates. Command execution and output must be bounded.

## Human-approved action

The only mutation authorized in this slice is generation of advisory improvement-proposal packets under `Soul/improvement/proposals/` after:

1. a read-only preview;
2. an exact assessment digest;
3. exact confirmation `GENERATE_SELF_IMPROVEMENT_PROPOSALS`;
4. revalidation that the assessed proposal revision is unchanged.

Proposal generation must not implement code, build a Beta, register a skill, apply an update, install or remove a package, invoke Codex, contact a cloud LLM, promote a candidate, merge, or release.

## Explicitly unavailable actions

OS updates, package installation/removal, orphan cleanup, service changes, model downloads, and privileged commands are not implemented by this phase. A future executor requires a separate human-approved brief with per-action previews, package-manager-specific semantics, timeouts, rollback/recovery guidance, and exact confirmations.

## Lifecycle

Every operation terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

No polling, watcher, schedule, daemon, background continuation, or automatic mutation is permitted.
