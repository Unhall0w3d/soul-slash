# Skill Candidate Review

## Skill

Name: Codex operational readiness A1

Risk class: Class 3

Date: 2026-09-23

## Candidate status

candidate_complete

## Implementation summary

- Added a redacted, on-demand Codex preflight based on the native `doctor --json`. It emits a timestamp, commit, dirty-worktree flag, and exact agent review outcomes, while explicitly declining to attest to the active app turn's model or permissions.
- Added an approval-evidence link validator and JSON schema. It reports a pending artifact/outcome mismatch without changing authority or the review packet.
- Tightened the existing input resolver to reject symlinked-parent escapes as well as symlinked final files.
- Added six synthetic policy scenarios and a deterministic scorer for separately collected, human-labeled traces. No live model trial is claimed.
- Added an opt-in foreground AMD workload gate using Soul's existing `amd-vulkan-generation` lease, reviewed RX 6900 XT identification, conservative foreign-allocation check before and after lease acquisition, bounded command runner, and release on exit.
- Documented exact existing host-operation routes. No broad privilege helper, sudoers entry, service, GPU scheduler, or new package was installed.
- Added a contextual pointer from Soul's `AGENTS.md`; routine repository edits do not load host procedures.

## Files changed

- `AGENTS.md`
- `Makefile`
- `config/codex_required_checks.json`
- `config/codex_policy_scenarios.json`
- `docs/guides/CODEX_OPERATIONAL_READINESS.md`
- `docs/soul/schemas/codex_approval_link.schema.json`
- `lib/soul_core/agent_execution_control_plane.rb`
- `lib/soul_core/external_amd_workload_gate.rb`
- `scripts/codex-policy-eval`
- `scripts/soul-agent-control-plane`
- `scripts/soul-amd-workload`
- `scripts/soul-codex-preflight`
- `scripts/verify-agent-operational-readiness-a1.rb`
- `scripts/verify-external-amd-workload-gate.rb`
- `docs/assessments/CODEX_OPERATIONAL_READINESS_A1_REVIEW.md`

## Commands run

- `ruby scripts/soul-codex-preflight`
- `ruby scripts/soul-amd-workload status 4` in the sandbox, then the same read-only status through an approved host escalation
- `ruby scripts/soul-amd-workload run 5 4 -- /usr/bin/true` through the approved host path; checked no `external.codex.amd` lease remained
- `make verify-agent-operational-readiness`
- `make verify-agent-execution-control-plane`
- Ruby syntax checks for each changed Ruby file
- JSON parsing of changed configuration/schema files
- `git diff --check`

## Deterministic test results

The A1 verifier covers approval links as non-authoritative evidence, reconciliation mismatch detection, path and symlinked-parent rejection, duplicate scope rejection, preflight redaction and active-turn uncertainty, policy fixture validity and scoring, AMD shared-lease use, blocked admissions, and lease release after success, timeout, and post-lease admission rejection. The existing A0 verifier continues to pass. The read-only AMD status was hidden by the sandbox (`vulkaninfo` could enumerate no device), then passed outside the sandbox for the reviewed `0000:0a:00.0` device with 14,885,109,760 bytes free against a 4 GiB threshold. A live foreground smoke test launched only `/usr/bin/true` for a five-second maximum and exited successfully; no `external.codex.amd` lease remained. This qualifies the admission/release path, not a real GPU workload or system-wide scheduling.

## Local LLM eval results

No live model trials were run. The six-scenario catalog and scoring interface are ready for retained, human-labeled traces; fixture validation is not a behavior qualification.

## Memory keys

Reads: none. Writes/updates: none. Forget behavior: not applicable.

## Lifecycle states touched

- `complete` for deterministic candidate checks.
- `blocked_for_human_review` for privilege deployment, sandbox-default changes, and live resource qualification not authorized by an exact operation brief.

## Safety and persistence check

- No root writes, sudo policy, persistent service, timer, network listener, or background worker added.
- No model, game, service, or GPU runtime was started or stopped; only `/usr/bin/true` ran under a short-lived lease.
- The AMD gate is opt-in, foreground, and advisory with respect to non-cooperating processes; it does not claim an OS-wide reservation.
- A linked approval claim never grants authority. Exact source and scope still require human verification.

## Known weaknesses

- Native `doctor --json` describes a separate CLI invocation; current app-turn model, sandbox, network, and writable roots must come from the active platform context.
- The current global policy names Astra as the ordinary baseline; the active task model and any user preference still require runtime verification. This candidate does not change either setting.
- The A0 review packet still records a pending human outcome; no old approval was inferred from conversation context.
- The policy suite scores human labels from retained traces; no live Astra/Sol behavior comparison is claimed.
- Non-cooperating apps can allocate AMD resources after admission; the gate cannot guarantee system-wide scheduling or protect an already running game.
- Root-scoped host operations still need an exact approved command/target and separate permission path before a wrapper can be installed.

## Human review checklist

- [ ] Preflight makes configured versus active-turn state unmistakable.
- [ ] Approval evidence remains separate from verified authority.
- [ ] Policy scenarios represent the expected decisions without overfitting prose.
- [ ] AMD gate is used only for explicitly requested, foreground external work and never presented as an OS-wide reservation.
- [ ] Confirm active-turn model and effort against the current Astra-baseline policy without treating this preflight as authority.
- [ ] Select exact privileged operation(s), if a root-owned wrapper is still desired.

## Human review outcome

Outcome: pending

Reviewer: operator

Decision summary: pending
