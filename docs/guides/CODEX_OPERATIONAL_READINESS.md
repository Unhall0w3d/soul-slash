# Codex operational readiness on Atelier

This is an on-demand route for Codex work, not a service or blanket authority.

## Before work that depends on the machine

1. Run `ruby scripts/soul-codex-preflight`. It uses the bundled Codex `doctor --json` and emits a small, timestamped configuration/repository/review summary without printing changed filenames. Its CLI invocation is **not** the current app turn: use the current turn's effective model, sandbox, writable roots, network, and approval context for authority. An inaccessible provider from a sandbox can make `doctor_status` fail without establishing an app outage.
2. Inspect the exact repository status and task-specific review packet. Distinguish a candidate, a deterministic check, a live qualification, a human decision, and a committed change. The A0 control-plane packet currently records `Outcome: pending`; reconcile it only against an exact operator decision and scope.
3. If a human decision needs to be linked to a review artifact, create an owner-reviewed JSON record matching `docs/soul/schemas/codex_approval_link.schema.json`, then run `scripts/soul-agent-control-plane approval-link FILE`. A valid link is evidence **about a claimed decision**, not verification of its source or a grant of authority. The tool flags an artifact whose recorded outcome still differs. Do not silently change the artifact.

## Host operations

Use an existing exact workflow rather than a general-purpose privileged account:

| Work | Existing route | Authority boundary |
| --- | --- | --- |
| Codex health/config | Bundled `codex doctor --json`; this guide's preflight | Read-only CLI observation, not current-turn attestation |
| Soul dashboard deployment | `SoulCore::DashboardDeployment#plan` / `#install` | Exact authorized owner-home and user-service mutation |
| Fleet maintenance | Guided Maintenance preview/execute and receipts | Remote mutation stays primary-owned and independently verified |
| Backup/restore | Backup Administration preview/execute and receipts | Exact snapshot/path scope, credentials kept out of chat and argv |
| `/etc`, root systemd, network or reboot | Existing reviewed deployment helper or an exact new root-owned wrapper | Separate operation-specific authorization, escalation, audit, and read-back |

No new sudoers rule, root account, background daemon, or generic command executor is installed by this work. A future privileged wrapper should be specified by exact binary, arguments, targets, owner, logging, rollback, and acceptance checks before implementation. Text in this guide cannot expand the active sandbox or grant root access.

## Behavior qualification

`ruby scripts/codex-policy-eval` validates the synthetic task catalog without contacting a model. Run each prompt in a fresh, appropriately permissioned Codex task and retain its answer and relevant tool trace. Human-label its decision in a `soul.codex.policy_observations.v1` JSON file; `ruby scripts/codex-policy-eval --score FILE` checks coverage and compares labels. This deterministic scorer does not establish that a human label is correct or that the model is safe in every context.

## External AMD work

`ruby scripts/soul-amd-workload status [MIN_FREE_GIB]` is read-only and advisory. `ruby scripts/soul-amd-workload run TIMEOUT_SECONDS MIN_FREE_GIB -- COMMAND [ARGS...]` is an opt-in foreground gate for an explicitly requested external workload. It reuses Soul's `amd-vulkan-generation` lease, checks reviewed RX 6900 XT identity and current foreign allocations, bounds child runtime, and releases its lease on exit. It does not start or stop a game, evict a model, or reserve the GPU against uncoordinated applications. Do not launch a swarm GPU worker through it while a game or other significant foreign allocation is active; a failed admission is a reason to wait or choose another resource, not to weaken the guard.
