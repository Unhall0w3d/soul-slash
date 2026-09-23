# Skill Candidate Review

## Skill

Name: Agent Execution Control Plane A0

Risk class: Class 3

Branch/checkpoint: current recovery worktree

Date: 2026-09-21

## Candidate status

candidate_complete

## Implementation summary

Added project-scoped mapper, implementer, and reviewer roles; established the
approved authority order; reconciled deterministic-testing and bounded-job
semantics; and added one native Ruby control-plane tool for assignment, review,
lifecycle, required-check, and advisory persistence evidence. The project
default remains `danger-full-access` pending the documented qualification.

## Files changed

- `.codex/agents/mapper.toml`
- `.codex/agents/implementer.toml`
- `.codex/agents/reviewer.toml`
- `AGENTS.md`
- `Makefile`
- `config/codex_required_checks.json`
- `docs/soul/AGENT_EXECUTION_CONTROL_PLANE_A0_BRIEF.md`
- `docs/soul/CODEX_TASK_PROMPT_TEMPLATE.md`
- `docs/soul/schemas/codex_subagent_assignment.schema.json`
- `docs/soul/schemas/skill_lifecycle_receipt.schema.json`
- `lib/soul_core/agent_execution_control_plane.rb`
- `scripts/soul-agent-control-plane`
- `scripts/verify-agent-execution-control-plane-a0.rb`
- `docs/assessments/CODEX_DANGER_FULL_ACCESS_A0_AUDIT.md`
- `docs/assessments/AGENT_EXECUTION_CONTROL_PLANE_A0_REVIEW.md`
- User-level `~/.codex/AGENTS.md` was normalized outside Git.

## Commands run

- Ruby syntax checks for the control-plane library, CLI, and verifier.
- Standard-library JSON parsing for both schemas and the check registry.
- Standard-library TOML parsing for all three custom roles.
- `make verify-agent-execution-control-plane`
- Read-only lexical inventory across `scripts/`, `lib/`, `deploy/`, `bin/`, and
  `config/` for exceptional host-access surfaces.

## Deterministic test results

PASS. The verifier covers valid and invalid assignment authority, unknown-field
rejection, lifecycle continuation evidence, review-packet completeness,
deduplicated path-to-check resolution, advisory persistence evidence,
out-of-repository rejection, symlink rejection, schema parsing, role sandbox
selection, and absence of pinned role models.

## Local LLM eval results

Not run. The changed behavior is configuration, schema validation, path safety,
and evidence classification. LLM evaluation would not establish these safety
properties.

## Memory keys

Reads: none.

Writes/updates: none.

Forget behavior: not applicable.

## Lifecycle states touched

- `complete` in the deterministic lifecycle fixture.
- `blocked_for_human_review` for promotion of this candidate and the later
  project-default sandbox change.

## Safety and persistence check

- Persistent service added: no
- Daemon added: no
- Watcher added: no
- Scheduled task added: no
- Cron job added: no
- systemd unit added: no
- Long-running background loop added: no
- Background polling added: no
- Confirmation gate weakened: no
- Skill-private memory store added: no
- Project default sandbox weakened: no; it remains unchanged

The persistence classifier is advisory, grants no authority, and reports exact
source evidence for review.

## Known weaknesses

- Parent-turn live permission overrides may supersede a role TOML; the primary
  must verify effective runtime authority.
- Required-check mapping identifies mandatory check classes but cannot infer the
  one correct feature-specific verifier for every future change.
- Persistence classification is lexical and may produce false positives or miss
  dynamically constructed behavior.
- The universal review validator checks structure and enumerated values, not the
  truthfulness or quality of the recorded evidence.
- `workspace-write` has not yet been live-qualified for loopback, hardware, or
  LAN acceptance paths.

## Curation corrections — 2026-09-23

The isolated candidate branch omits `.codex/config.toml`; its existing
`danger-full-access` and `approval_policy = "never"` values are not promoted.
`Makefile` retains the verifier targets but omits the five path-bearing
convenience recipes, whose Make-variable expansion would pass caller-controlled
path text through a shell. The direct CLI takes exact argv for validation,
required-check mapping, and advisory persistence inspection. The repository
policy now states the authority order locally, so a separate machine-wide
policy is not required to understand its precedence. These changes add no
runtime service or approval authority.

## Human review checklist

- [ ] Role descriptions and sandbox boundaries match intended use.
- [ ] Authority order correctly separates authorization from safeguards.
- [ ] Assignment and lifecycle schemas contain the required common language.
- [ ] Universal review validation is strict enough without implying approval.
- [ ] Required-check mapping remains understandable and maintainable.
- [ ] Persistence findings remain advisory.
- [ ] Danger-full-access audit is adequate before live qualification.
- [ ] No project-default sandbox change is promoted in this candidate.

## Human review outcome

Outcome: pending

Reviewer: operator

Date: pending

Decision summary: pending

Required changes: pending
