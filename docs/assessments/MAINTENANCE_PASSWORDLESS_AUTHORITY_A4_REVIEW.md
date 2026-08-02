# Maintenance Passwordless Authority A4 Review

> **Historical artifact.** A11 supersedes the unattended AUR behavior recorded
> here. Current implementation removes AUR code from the root helper and
> requires a separate interactive review gate.

Status: A2 maintenance and separate reboot-only A3 live-accepted on 2026-07-29;
A4 v4 installed exactly on 2026-08-01 after repairing yay install-reason
bookkeeping exposed by a successful upgrade

## What was implemented

- Added opt-in `SOUL_MAINTENANCE_PASSWORDLESS` authority while preserving
  native one-password A2/A3 behavior as the public default.
- Added a deterministic deployment plan for one root-owned helper and one
  sudoers fragment. The sudoers rule binds the helper bytes by SHA-256 and
  grants no direct passwordless package manager, reboot tool, interpreter, or
  shell.
- Added fixed operations for a target-free Arch/AUR full upgrade, system
  Flatpak update, and A3-journal-gated reboot.
- Added yay 13.0.1 native unattended policy flags: decline clean rebuilds,
  diffs, PKGBUILD edits, and make-dependency removal; select the reviewed
  upgrade set; proceed without routine input.
- A4 v4 admits only yay 13.0.1's exact post-install
  `pacman -D --asexplicit -q --noconfirm --config /etc/pacman.conf -- <name>`
  bookkeeping vector while the exact active yay process remains transaction
  bound. Every other package-database operation remains rejected.
- A4 v3 runs yay under the qualified desktop UID/GID instead of root. Its
  privileged pacman calls return through a transaction-scoped helper bridge
  that is accepted only through a bounded chain of exact sudo processes
  descended from the exact active yay PID/start identity.
  The bridge rejects removals, other pacman database operations, alternate roots,
  alternate database/cache/hook/log/keyring paths, changed configuration,
  non-package-manager executables, and calls outside the active reviewed
  transaction.
- Added root-owned `/run` phase state so privileged operations advance in the
  reviewed order and a completed transaction cannot replay before reboot.
- Extended A2/A3 transaction and receipt evidence with authority mode and zero
  password-prompt accounting.
- The confined Dashboard verifies the exact installed helper digest and defers
  the sudoers execution proof to the native desktop handoff. This preserves
  `NoNewPrivileges`; a missing or changed sudoers rule fails before any update.
- The device-scoped Maven dialog keeps native-evidence recovery outside its
  scrollable plan, names the exact blockers, provides a separate preflight
  recheck, and displays zero-password A4 authentication accurately.
- A2 package-only plan digests no longer bind window/workspace restoration
  inventory. Closing the evidence terminal cannot invalidate a maintenance
  authorization; A3 reboot retains its separate fresh snapshot and restore
  gates.
- Kept the foreground terminal for audit, cancellation, bounded execution, and
  failure evidence.

## Files changed

- `.env.example`
- `Makefile`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/maintenance_foreground_execution_service.rb`
- `lib/soul_core/maintenance_desktop_handoff.rb`
- `lib/soul_core/maintenance_passwordless_authority.rb`
- `lib/soul_core/maintenance_reboot_restore_service.rb`
- `lib/soul_core/maintenance_transaction_runner.rb`
- `scripts/soul-maintenance-authority`
- `scripts/soul-maintenance-authority-root`
- `scripts/verify-maintenance-passwordless-authority-a4.rb`
- `docs/soul/MAINTENANCE_PASSWORDLESS_AUTHORITY_A4_BRIEF.md`
- `docs/soul/schemas/maintenance_transaction.schema.json`
- `docs/soul/schemas/maintenance_receipt.schema.json`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/ROADMAP.md`
- `config/project_tracker_seed.json`

## Commands run

```text
ruby -c lib/soul_core/maintenance_passwordless_authority.rb
ruby -c lib/soul_core/maintenance_foreground_execution_service.rb
ruby -c lib/soul_core/maintenance_transaction_runner.rb
ruby -c lib/soul_core/maintenance_reboot_restore_service.rb
ruby -c scripts/soul-maintenance-authority
ruby -c <generated root helper>
ruby bin/soul config validate
make verify-maintenance-passwordless-authority
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
make verify-maintenance-reboot-restore
make verify-maintenance-device-control
git diff --check
```

## Deterministic results

- Public passwordless mode remains off.
- The installation plan and helper digest are stable.
- Wrong digest or confirmation performs no privileged installation call.
- Sudoers names only the digest-bound helper's fixed operation shapes.
- Caller-controlled executables, package targets, paths, flags, and answers
  are rejected.
- The generated helper drops UID, GID, and supplementary-group authority
  before starting yay; only its recorded PID/start identity, reached through
  at most three exact sudo ancestors, can invoke the constrained pacman
  bridge.
- Passwordless transactions contain no sudo validation, keeper, or
  invalidation call and record zero prompts.
- Altered vectors and direct pacman execution fail before execution.
- Native A2/A2B/A3 regressions remain passing.
- Confined `NoNewPrivileges` status remains usable without claiming that the
  Dashboard itself can elevate.
- Stale Maven evidence exposes a prominent recovery and recheck path instead of
  leaving only a disabled device-action button.
- Changing windows or workspaces between A2 preview and click leaves the
  package-only digest stable.
- The native desktop handoff atomically claims a reviewed transaction at the
  canonical ID-derived path required by the root helper; the suffixed
  reservation remains single-use and cannot replay.
- The supervised 2026-07-29 A2 run completed the Arch/AUR full upgrade and
  system Flatpak update with zero password prompts, no reboot request, a
  closed sudo lifecycle, and one redacted terminal receipt.
- The 2026-08-01 retained failure was a false-negative terminal state after 47
  native upgrades and the `webex-bin` AUR upgrade completed. The v3 bridge
  rejected yay's final `--asexplicit` bookkeeping call, so yay returned 1 and
  the separate Flatpak phase did not run. A4 v4 adds deterministic coverage for
  that exact vector without permitting arbitrary pacman database mutation.
- The Operator approved deployment digest
  `044448c8010277b9e66a2dab50dd24eab23f84b38e4b7a4e2a83b1733022d2ac`.
  The installed root-owned helper reports `soul-maintenance-authority-a4-v4`,
  matches SHA-256
  `1394aa18dff9f8c5c469b5a59a93ce94126b73dd802a811543a62ea56ce34951`,
  and passed the native passwordless self-check. Installation did not run a
  package transaction or reboot.

## Local LLM eval results

None. Privileged command policy, prompt defaults, replay behavior, and reboot
authorization are deterministic safety boundaries and cannot be approved by a
model.

## Known weaknesses

- The first reboot-only transaction attempted through the uniform Atelier UX
  failed closed before mutation because the desktop handoff still expected the
  pre-A4 direct `systemctl reboot` vector. The handoff now selects its exact
  reboot allowlist from `authority_mode`, with deterministic coverage for both
  accepting the A4 helper vector and rejecting the legacy direct vector under
  passwordless authority.

- Passwordless local authority cannot distinguish the Dashboard from another
  process already running as the same desktop owner. Such a process may request
  the same fixed full-maintenance preview, but cannot create a valid reviewed
  transaction silently or use the pacman bridge outside the recorded active
  yay process.
- Pacman and yay native noninteractive defaults may accept ordinary
  full-upgrade replacements or removals. They cannot be made both fully
  unattended and individually human-reviewed. Errors and decisions not
  resolved by the qualified native policy stop the transaction.
- The helper is version-qualified to yay 13.0.1. A yay update intentionally
  disables A4 until a new helper is reviewed and installed.
- Earlier retained failures exposed three fail-closed integration defects:
  root-owned AUR builds, a handoff/canonical transaction-path mismatch, and
  sudo's additional monitor ancestry. A4 v3 repairs all three without
  broadening the fixed-operation surface.
- A4 v3 also rejected yay's bounded post-install `--asexplicit` call. A4 v4
  narrows the exception to one exact flag order, the fixed pacman configuration,
  one to 128 package-name tokens, and the already-bound active yay ancestry.
- The zero-prompt A3 authority and reboot boundary are accepted. The first
  successful reboot-only receipt retained two bounded application failures
  (Webex and Opera); these do not broaden or invalidate A4 and remain
  application-level follow-up for a natural future reboot.

## Memory keys added or used

None. Transactions, root phase state, journals, and receipts are operational
state rather than conversational memory.

## Task lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`
- `awaiting_login` for the existing A3 path

## Risk classification

Class 5. A4 installs reusable but narrowly bounded local privilege. It stores
no password and exposes no general command runner.

## Human review checklist

- [x] Review the A4 brief and residual-risk statement.
- [x] Confirm the native one-password path remains the public default.
- [x] Confirm no package manager, reboot tool, shell, or interpreter is
  directly passwordless.
- [x] Confirm routine yay choices are fixed constants rather than model
  decisions.
- [x] Inspect and install the A4 v1 helper and sudoers plan.
- [x] Confirm A4 v1 exact self-check and arbitrary-operation rejection.
- [x] Enable the ignored local A4 flag.
- [x] Inspect and install the corrected A4 v3 helper and sudoers plan.
- [x] Inspect and install the A4 v4 install-reason repair.
- [x] Run one supervised A2 transaction with zero
  prompts.
- [ ] Run one later A3 reboot/restore transaction with zero prompts and no
  package commands.
- [x] Accept A4 for package-only A2 maintenance.
- [ ] Accept, revise, or uninstall A4 for A3 after the separate reboot test.
