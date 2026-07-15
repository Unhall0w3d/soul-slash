# Phase 12D Approved Brief: Skill Studio Proposal and Beta Lifecycle

```text
brief_status: approved from human direction dated 2026-07-15
implementation_authorized: yes
human_visual_review_required: yes
human_merge_review_required: yes
```

## Purpose

Connect Skill Studio to Soul's existing skill proposal and alpha-candidate infrastructure without creating a second skill runtime or allowing generated material to authorize itself.

The user-facing maturity name is `Beta`. Existing proposal-local `alpha/` artifacts remain readable as legacy scaffolds, but a runnable Beta must contain implemented behavior and deterministic test evidence.

## Human authority gates

### Gate 1: proposal approval

The human reviews a proposal and approves its exact content digest for Beta implementation. Approval permits bounded implementation work only. It does not generate working code, invoke Codex, register a skill, execute a skill, or approve production promotion.

### Gate 2: Beta approval

The human reviews an implemented Beta, its exact content digest, deterministic test results, required test checklist, diagnostics, and known weaknesses. Approval marks that revision `approved_for_promotion`. It does not copy files into production, alter the production registry, merge code, or bypass a later promotion workflow.

## Approved scope

Phase 12D may:

- list and inspect ignored proposal packets under `Soul/proposals/skills/`;
- adapt older proposal metadata into a bounded Skill Studio projection without silently rewriting it;
- record Gate 1 approval beside the proposal using an exact confirmation and unchanged digest;
- list implemented proposal-local Betas separately from production skills;
- expose descriptions, declared inputs, lifecycle, risk, test requirements, latest test evidence, and promotion readiness;
- list legacy `alpha/` scaffolds as non-runnable migration candidates;
- permit an implemented Beta to run only after an explicit human preview and exact confirmation;
- write bounded, local diagnostic JSONL records for Beta executions;
- record Gate 2 approval of an unchanged, passing Beta revision;
- derive and expose the proposal's current lifecycle stage and exact linked Beta/production skill ID;
- allow preview-gated closeout only after exact production registration under the separately approved Phase 12D.4 amendment;
- expose these operations through the existing in-process application facade and foreground dashboard;
- add deterministic tests and a human review artifact.

## Beta package contract

A runnable Beta lives at:

```text
Soul/proposals/skills/<proposal-id>/beta/
```

It contains at minimum:

```text
beta_manifest.json
skill.rb
test_results.json
```

The manifest declares a stable skill ID, description, bounded entrypoint, risk, lifecycle states, required tests, execution timeout, and whether implementation is complete. Entrypoints cannot escape the Beta directory. Runtime is bounded to 60 seconds, argument count and size are limited, output is capped, and no retry occurs.

## Explicit prohibitions

Phase 12D must not:

- treat a Mistral draft or review as human approval;
- automatically invoke Codex or apply implementation patches;
- claim an alpha behavior scaffold is a working Beta;
- register or promote Beta code into `Soul/skills/registry.yaml`;
- allow Soul or an LLM to self-authorize a Beta run;
- run a Beta in the background or after the request returns;
- add a service, daemon, watcher, poller, scheduler, or persistent listener beyond the separately approved foreground dashboard;
- expose arbitrary proposal files, secret values, unrestricted logs, or filesystem paths through the dashboard;
- weaken production skill confirmation or safety gates.

## Terminal states

Every Skill Studio operation terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Done criteria

- Proposal and Beta lists are separate from the production skills list.
- Gate 1 is revision-bound and human-only.
- Scaffold-only alpha artifacts are visibly non-runnable.
- Beta execution is preview-first, exact-confirmation-only, bounded, foreground, and logged.
- Gate 2 requires unchanged code plus passing declared test evidence.
- Gate 2 records approval for promotion without performing promotion.
- Dashboard content uses safe DOM construction and no polling.
- Deterministic verification and the required human review artifact are present.
