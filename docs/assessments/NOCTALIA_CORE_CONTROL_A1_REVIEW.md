# Noctalia Core Control — A1 Review

## Candidate

- Name: bounded five-Core control from Noctalia
- Risk class: moderate local model-runtime mutation
- Status: candidate-complete; deterministic validation passed; live Operator
  review pending after coordinated merge
- Human authority: separate preview selection and exact activation click

## Implemented

- Added a bounded five-Core inventory to `soul.noctalia.status.v2`.
- Added a dedicated `soul.noctalia.core_control.v1` projection over the existing
  `CoreOrchestrationService` preview and execute gates.
- Added strict Core, profile, confirmation, and digest validation to the
  foreground companion CLI.
- Kept the full pending preview only in Noctalia service memory.
- Added a focused Core picker that temporarily replaces the fleet surface,
  preventing panel-height regression.
- Added a separate review card and activation click, with terminal progress and
  status refresh.
- Preserved Soul's active-work, idle-certainty, target-membership, confirmation,
  and digest-drift blockers.

## Files changed

```text
Makefile
bin/soul-noctalia
lib/soul_core/noctalia_core_control_service.rb
lib/soul_core/noctalia_status_service.rb
scripts/verify-noctalia-companion-a0.rb
docs/soul/NOCTALIA_CORE_CONTROL_A1_BRIEF.md
docs/soul/schemas/noctalia_status.schema.json
docs/soul/schemas/noctalia_core_control.schema.json
docs/assessments/NOCTALIA_CORE_CONTROL_A1_REVIEW.md
config/project_tracker_seed.json

Public plugin repository:
catalog.toml
overview/service.luau
overview/panel.luau
overview/plugin.toml
overview/README.md
scripts/verify-public-source.rb
```

## Verification

```text
ruby -c lib/soul_core/noctalia_core_control_service.rb
ruby -c lib/soul_core/noctalia_status_service.rb
ruby -c bin/soul-noctalia
PASS

make verify-noctalia-companion
PASS — 22 deterministic checks

ruby scripts/verify-core-orchestration.rb
PASS — five-Core, stale-digest, active-work, virtual-runtime, and Dashboard
contract checks

bin/soul-noctalia status
PASS — live Soul-Lite Core plus five bounded Core choices

bin/soul-noctalia core-preview --core daily
PASS — read-only Soul-Lite → Soul Core preview; exact digest and confirmation
present; service mutation disclosed; no Core change

Public plugin repository:
ruby scripts/verify-public-source.rb
PASS — no environment-specific values or resolved targets

noctalia plugins lint overview
PASS — 0 errors, 0 warnings

git diff --check
PASS in both repositories
```

## Lifecycle and memory

- Lifecycle states: `complete`, `failed`, `awaiting_input`,
  `blocked_for_human_review`.
- Runtime: bounded foreground command with 15-second preview and 120-second
  execution timeout at the Noctalia boundary.
- Retries: none automatic.
- Pending gate retention: process memory only; canceled or lost on reload.
- Shared memory keys: none.
- Skill-private memory: none.
- Persistent services, listeners, schedules, or watchers added: none.

## Local LLM eval

Not run. This candidate is deterministic local authority plumbing and UI state,
not conversational routing or generated behavior.

## Known weaknesses

- Noctalia Luau lacks a standalone unit harness; live plugin loading remains a
  required review step.
- A status refresh can occur while a preview is open. Soul's execute-time digest
  and active-work checks remain authoritative and will reject drift.
- Core activation may take long enough to reach the 120-second UI timeout on a
  severely loaded host; Soul still terminates according to its own bounded
  service-control path.

## Human review checklist

```text
[ ] Core picker shows exactly five current labels
[ ] Active Core is selected and cannot be activated again
[ ] Selecting another Core performs preview only
[ ] Review card explains source, target, purpose, and runtime mutation
[ ] Cancel discards the pending preview
[ ] Activate changes only the reviewed Core and refreshes status
[ ] Active work blocks switching with a useful message
[ ] Free Core shows no model loaded
[ ] Dev Core identifies its development lane accurately
[ ] Voice Presence and fleet controls remain unchanged after returning
```
