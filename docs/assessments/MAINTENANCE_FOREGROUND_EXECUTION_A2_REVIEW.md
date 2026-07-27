# Maintenance Foreground Execution A2 Review

Status: candidate-complete; human review required

## What was implemented

- Added a typed A2 execution preview that reuses fresh A1 evidence and adds
  fixed executable, package-lock, disk-space, active-work, and transaction-lock
  gates.
- Qualified installed `yay` 13.0.1 and uses
  `--sudoflags=-n` while leaving yay's own `sudoloop` disabled.
- Added one fixed foreground kitty launcher. It waits for the terminal process
  and has a four-hour hard deadline; it does not detach an updater.
- Added a transaction runner with one native `sudo -v` prompt, a parent-owned
  bounded ticket refresh, noninteractive subsequent privilege calls, and
  `sudo -k` invalidation on every terminal path.
- Added strict command allowlisting for normal `-Syu`, explicit forced-refresh
  `-Syyu`, user Flatpak, and system Flatpak updates. No shell parses command
  text.
- Added cancellation and failure handling, digest replay protection, atomic
  owner-private redacted receipts, a 30-receipt cap, and a complete prohibition
  on reboot.
- Added an Administration review card with click authority, live progress,
  receipt evidence, a visible no-mutation terminal rehearsal, and a disabled
  live-update control.
- Added a typed `SOUL_MAINTENANCE_A2_LIVE` setting whose portable and local
  default remains `false`.

The implementation includes the live runner, but live execution is disabled.
No package update, sudo authentication, or reboot was performed during
candidate verification.

## Files changed

- `.env.example`
- `Makefile`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `config/invocation_catalog.yaml`
- `config/project_tracker_seed.json`
- `docs/CURRENT_STATE.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/MAINTENANCE_FOREGROUND_EXECUTION_A2_BRIEF.md`
- `docs/soul/schemas/maintenance_execution_plan.schema.json`
- `docs/soul/schemas/maintenance_transaction.schema.json`
- `docs/soul/schemas/maintenance_transaction_result.schema.json`
- `docs/soul/schemas/maintenance_receipt.schema.json`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/dashboard_capability_guide.rb`
- `lib/soul_core/maintenance_foreground_execution_service.rb`
- `lib/soul_core/maintenance_transaction_runner.rb`
- `lib/soul_core/voice_screen_understanding_service.rb`
- `scripts/soul-maintenance-transaction`
- `scripts/verify-maintenance-foreground-execution-a2.rb`
- `docs/assessments/MAINTENANCE_FOREGROUND_EXECUTION_A2_REVIEW.md`

## Commands run

```text
yay --version
yay --help
yay -Pg
kitty --version
ruby -c lib/soul_core/maintenance_foreground_execution_service.rb
ruby -c lib/soul_core/maintenance_transaction_runner.rb
ruby -c scripts/soul-maintenance-transaction
node --check assets/dashboard/dashboard.js
make verify-maintenance-foreground-execution
make verify-maintenance-rehearsal
ruby scripts/verify-dashboard-self-improvement-navigation.rb
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-dashboard-capability-guide-a1.rb
ruby scripts/verify-perception-a3.rb
ruby scripts/verify-invocation-catalog-a1.rb
ruby scripts/verify-project-timeline-a1.rb
ruby scripts/verify-private-memory-separation.rb
checkupdates --nocolor
systemctl --user restart soul-dashboard.service
git diff --check
```

## Deterministic test results

The focused A2 verifier covers:

- stable exact-digest previews;
- fixed `yay --sudoflags=-n` and Flatpak vectors;
- package-lock, active-work, executable, and disk-space blockers;
- separate common rehearsal blockers and live-only package/sudo-confinement
  blockers;
- wrong confirmation and stale digest rejection before terminal launch;
- digest stability across harmless free-space fluctuations while the current
  threshold is still revalidated;
- fixture-only rehearsal with zero password prompts and zero host commands;
- private, atomic, redacted receipts;
- default-disabled live execution;
- single-use live digest behavior under injected fixtures;
- one validation prompt, ticket invalidation, and zero reboot authority;
- strict shell/unallowlisted-vector rejection before authentication;
- typed facade exposure and JSON schema validity; and
- click authority, no Dashboard password input, and timer-free UI behavior.

All focused checks pass. The live Dashboard fixture rehearsal also completed:
four simulated stages, zero password prompts, an invalidated unused ticket,
zero reboot authority, one private receipt, and no surviving runner.

## Local LLM eval results

None. Privilege boundaries, command vectors, replay protection, package locks,
cancellation, receipt privacy, and reboot prohibition are deterministic safety
behavior and must not be delegated to a model.

## Known weaknesses

- The real sudo/yay interaction has not been exercised because a live package
  update is not authorized.
- The installed dashboard unit sets `NoNewPrivileges=true`, which correctly
  appears as a live-only blocker because a child terminal cannot perform native
  `sudo -v`. Enabling live A2 requires a separately reviewed design decision;
  this candidate does not weaken the service sandbox.
- `checkupdates` succeeds from an ordinary host terminal but cannot refresh
  package metadata inside the installed dashboard service sandbox. This remains
  a second visible live-only blocker. A cached or failed check is never
  misrepresented as fresh evidence.
- A terminal connection disappearing while the visible runner remains active is
  bounded by the terminal owner and four-hour deadline, but needs live
  observation.
- Active-work detection covers persisted music jobs, model leases, and the
  backup operation lock. New long-running subsystems must register before A2
  live enablement.
- Free-space thresholds are conservative fixed minimums rather than a
  per-package download/install estimate.
- `yay` behavior is qualified against installed version 13.0.1. Other public
  installations must expose the reviewed `--sudoflags` behavior or fail closed.
- Package prompts may still require human judgment. Soul does not answer them.
- A2 intentionally does not merge `.pacnew`, clean orphans/caches, retry failed
  builds, close applications, reboot, or restore a workspace.

## Memory keys added or used

None. Maintenance authority and receipts are operational state, not
conversational memory.

Owner-private state:

```text
Soul/private/host_maintenance/
```

It contains only bounded transaction files, the operation lock, and the newest
30 redacted receipts.

## Task lifecycle states touched

- `complete`
- `awaiting_input`
- `failed`
- `canceled`
- `blocked_for_human_review`

No transaction may remain silently running after its visible terminal reaches a
terminal lifecycle.

## Risk classification

Class 5.

The candidate contains a privileged package-update path. Its tracked default
and the current local default are disabled. Enabling it later permits one
digest-bound foreground update but still grants no reboot authority.

## Safety and persistence check

```text
Password accepted by Dashboard, Chat, Voice, file, argv, or env: no
Native sudo prompts permitted per transaction: at most one
Subsequent sudo calls: fixed noninteractive argv only
Shell or model-generated command arguments: no
yay sudoloop: disabled
Detached updater or reusable root helper: no
Automatic prompt answers or --noconfirm: no
Automatic retry: no
Live update performed during candidate verification: no
Reboot path present in A2: no
Persistent service, timer, daemon, watcher, or scheduler added: no
Receipt contains password, terminal input, or raw environment: no
```

## Human review checklist

- [ ] Confirm A2 remains disabled in the effective configuration.
- [ ] Review every fixed command vector.
- [ ] Confirm yay 13 uses `--sudoflags=-n` and `sudoloop` remains false.
- [ ] Confirm the Dashboard contains no password field.
- [ ] Confirm Chat and Voice cannot authorize A2.
- [ ] Review active-work and free-space blocker coverage.
- [x] Run the visible fixture-only terminal rehearsal.
- [x] Inspect the resulting redacted receipt and surviving processes.
- [ ] Approve the candidate, request repair, or reject it.
- [ ] Do not enable the first real update without a later exact authorization.
- [ ] Do not begin A3 solely because A2 deterministic tests pass.
