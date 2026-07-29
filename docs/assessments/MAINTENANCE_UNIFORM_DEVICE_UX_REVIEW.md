# Uniform Maintenance Device UX Review

## Candidate

The workstation now presents the same visible lifecycle as other supported
managed devices:

`updates available → Maintain → bounded completion → refreshed card → Reboot`

Reboot is never inferred or chained from maintenance. It remains a separate
reviewed action.

## What was implemented

- Removed the workstation-only manual **Refresh evidence** and **Recheck
  preflight** controls from the device dialog.
- When workstation native package evidence is stale or missing, opening
  **Maintain** or **Reboot** reserves and opens one existing read-only desktop
  evidence handoff automatically.
- Added a finite two-minute evidence poll tied to the open dialog. It stops on
  readiness, a different blocker, dialog close, or timeout.
- Reused the common prefilled, read-only approval gate. The final action click
  remains the human authorization for the exact preview digest.
- Added a finite 30-minute maintenance-receipt poll tied to the exact
  transaction ID. A matching complete receipt triggers a fresh fleet
  collection and card render.
- Kept reboot outside the maintenance completion path. The reboot button
  obtains its own A3 preview, restore journal, digest, and approval.
- Corrected the legacy A3 executor so the separately presented reboot action
  requires an empty package-command list. A3 now captures, reboots, and
  restores without replaying `yay` or Flatpak.
- Replaced the workstation card label **Maintenance** with the action-oriented
  **Maintain**.

## Files changed

- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.css`
- `lib/soul_core/maintenance_reboot_restore_service.rb`
- `lib/soul_core/maintenance_transaction_runner.rb`
- `docs/soul/schemas/maintenance_transaction.schema.json`
- `scripts/verify-maintenance-device-control-c1.rb`
- `scripts/verify-maintenance-foreground-execution-a2.rb`
- `scripts/verify-maintenance-reboot-restore-a3.rb`
- `scripts/verify-maintenance-passwordless-authority-a4.rb`
- `docs/soul/MAINTENANCE_REBOOT_RESTORE_A3_BRIEF.md`
- `docs/assessments/MAINTENANCE_REBOOT_RESTORE_A3_REVIEW.md`
- `docs/assessments/MAINTENANCE_PASSWORDLESS_AUTHORITY_A4_REVIEW.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `config/project_tracker_seed.json`
- `docs/assessments/MAINTENANCE_UNIFORM_DEVICE_UX_REVIEW.md`

## Deterministic checks

Run:

```text
node --check assets/dashboard/dashboard.js
make verify-maintenance-device-control
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
make verify-maintenance-reboot-restore
make verify-maintenance-passwordless-authority
make verify-maintenance-fleet-status
make verify-project-timeline
git diff --check
make test-fast
```

## Local LLM evaluation

Not applicable. This slice changes deterministic Dashboard orchestration and
does not use model output for routing, safety, authorization, or execution.

## Live read-only smoke check

After restarting the Dashboard, the Atelier card rendered separate **Maintain**
and **Reboot** controls. Opening **Maintain** with stale evidence entered the
automatic evidence state. The in-app browser cannot dispatch the custom local
desktop URI, so the exact reserved read-only URI was completed through the
installed native handler. The open dialog advanced automatically to the
reviewed A4 plan, displayed the fixed helper vectors, and exposed an enabled
read-only **Maintain Atelier** click gate. The dialog was closed without
executing maintenance.

## Known weaknesses

- The Dashboard can observe completion only while the device dialog remains
  open. Closing it intentionally stops browser-side polling; the visible
  terminal and retained receipt remain authoritative.
- The browser cannot cancel the terminal-owned transaction by closing the
  dialog.
- A live zero-prompt A3 workstation reboot/restoration through this exact UX
  remains pending Operator acceptance.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Private state read: native package evidence, exact maintenance reservation,
  exact receipt, and fleet snapshot through existing services.
- Lifecycle states: `complete`, `failed`, `awaiting_input`,
  `blocked_for_human_review`.
- No watcher, daemon, service, scheduled task, or background continuation was
  added.

## Risk classification

Class 5 presentation/orchestration change over existing privileged,
digest-bound maintenance operations. The fixed command surface, root helper,
preflight checks, approval digest, terminal ownership, and separate reboot
gate are unchanged.

## Human review checklist

- [ ] Opening workstation **Maintain** with stale evidence opens one visible
  evidence terminal and becomes review-ready without a manual recheck.
- [ ] The approval phrase is prefilled and cannot be edited.
- [ ] Clicking **Maintain** opens one visible bounded transaction.
- [ ] A complete exact receipt refreshes the workstation card automatically.
- [ ] Maintenance does not reboot.
- [ ] Reboot runs no `yay`, pacman, or Flatpak command.
- [ ] A reported reboot requirement leaves **Reboot** as a separate action.
- [ ] The separately approved workstation reboot restores the reviewed
  applications and display state.
