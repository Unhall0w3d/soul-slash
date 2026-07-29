# Maintenance Conditional Reboot and Restore A3 Review

Status: accepted on the Operator workstation after supervised native and
zero-prompt live reboots; individual application restoration remains
non-blocking refinement; public live gates disabled

## Implementation summary

- Added a separately typed and disabled `SOUL_MAINTENANCE_A3_LIVE` gate.
- Added an A3 Dashboard preview that binds the A2 update evidence, restore
  registry, source boot ID, reboot permission, and exact resume-unit state into
  one reviewed digest.
- Extended the existing single-use desktop handoff with a distinct
  `live_reboot` transaction while preserving the non-rebooting A2 path.
- Extended the visible foreground runner to write a durable restore journal
  only after all reboot postconditions revalidate.
- Applied the Operator's 2026-07-29 separation decision: `live_reboot`
  transactions now require an empty command list and reject any attempted
  package-maintenance replay. Historical accepted A3 transactions included
  updates; future **Reboot** actions do not.
- Added one authority-mode-specific exact reboot vector: native-prompt mode
  uses `/usr/bin/sudo -n /usr/bin/systemctl reboot`; A4 uses its
  transaction-bound root helper.
- Added one bounded post-login restorer that verifies owner, digest, boot
  change, deadline, restore-registry revision, and retry limits before launching
  or placing an application.
- Added an exact-plan deployment for an owner-level
  `soul-maintenance-resume.service` oneshot unit. Installation enables but never
  starts it.
- Added terminal journal archival and redacted receipts for complete, partial,
  stale, same-boot, and invalid restore outcomes.
- Standardized the installed one-shot unit and native handoff on
  `/usr/bin/ruby`, avoiding shell-specific rbenv path drift.
- Added owner-validated discovery of the live Hyprland runtime socket so the
  post-login unit does not depend on inherited compositor variables.
- Migrated display wake, workspace placement, window-state restoration, and
  workspace focus to Hyprland's current typed Lua dispatchers.
- Added an optional bounded, owner-only local display-recovery hook. The public
  default is empty; Maven uses its existing DP-3 retrain script.
- Added Maven-reviewed Webex and Teams for Linux restore entries. Their exact
  window classes and process names are allowlisted with fixed launch vectors;
  each is restored only when represented in the pre-reboot window/process
  snapshot and skipped if already running after autologin.
- Corrected Webex restoration to use the same fixed Wayland environment as the
  Operator's successful desktop-menu entry.
- Stabilized the A3 review digest by binding the already normalized A2 plan
  digest and exact A3 blockers instead of volatile raw free-space byte counts.
- Preserved A2's package-only digest boundary while restoring the real A3
  integration: the foreground service projects current restore-registry and
  window-summary evidence beside, rather than inside, the A2 plan. A3 binds
  that read-only evidence into its own independently reviewed digest.
  Raw disk evidence remains visible in every preview.

## Files changed

- `.env.example`
- `Makefile`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/maintenance_desktop_handoff.rb`
- `lib/soul_core/maintenance_reboot_coordinator.rb`
- `lib/soul_core/maintenance_reboot_restore_service.rb`
- `lib/soul_core/maintenance_rehearsal_service.rb`
- `lib/soul_core/maintenance_resume_deployment.rb`
- `lib/soul_core/maintenance_session_restorer.rb`
- `lib/soul_core/maintenance_transaction_runner.rb`
- `scripts/soul-maintenance-resume`
- `scripts/soul-maintenance-resume-service`
- `scripts/soul-maintenance-transaction`
- `scripts/verify-maintenance-reboot-restore-a3.rb`
- `docs/soul/schemas/maintenance_restore_journal.schema.json`
- `docs/soul/schemas/maintenance_receipt.schema.json`
- `docs/soul/schemas/maintenance_transaction.schema.json`
- `docs/soul/schemas/maintenance_transaction_result.schema.json`
- `docs/soul/MAINTENANCE_REBOOT_RESTORE_A3_BRIEF.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/assessments/MAINTENANCE_REBOOT_RESTORE_A3_REVIEW.md`
- `config/project_tracker_seed.json`

## Commands run

```text
ruby -c lib/soul_core/maintenance_reboot_coordinator.rb
ruby -c lib/soul_core/maintenance_session_restorer.rb
ruby -c lib/soul_core/maintenance_resume_deployment.rb
ruby -c lib/soul_core/maintenance_reboot_restore_service.rb
ruby -c lib/soul_core/maintenance_transaction_runner.rb
ruby -c scripts/soul-maintenance-resume
ruby -c scripts/soul-maintenance-resume-service
node --check assets/dashboard/dashboard.js
make maintenance-resume-plan
make verify-maintenance-reboot-restore
make maintenance-resume-install CONFIRM=INSTALL_SOUL_MAINTENANCE_RESUME
make maintenance-resume-status
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
make verify-maintenance-rehearsal
make verify-project-timeline
ruby scripts/verify-phase12b-in-process-application-api.rb
git diff --check
```

## Deterministic results

The focused verifier proves:

- A3 writes its private journal before requesting one fixed reboot;
- authentication remains one prompt and the sudo ticket is invalidated;
- A2 remains incapable of reboot;
- the tracked A3 default remains disabled;
- the Dashboard reserves a handoff but does not reboot inside its confined
  process;
- safe raw disk-space fluctuations do not invalidate an otherwise exact
  reviewed A3 plan;
- package lock, active Soul work, missing resume unit, unavailable reboot
  permission, changed registry, changed boot identity, stale journal, same-boot
  journal, and journal tampering fail closed;
- unsupported applications are never launched;
- already-running background applications are not duplicated;
- Maven's current native snapshot maps running Webex and Teams for Linux to
  their exact fixed launch vectors on workspace 4/monitor 1 without retaining
  titles or raw process arguments;
- partial restoration uses at most one retry and terminates for human review;
- completed restoration consumes the journal and a later unit invocation is a
  no-op;
- installation requires exact confirmation and never starts the resume unit;
  and
- the unit contains no restart policy, timer, listener, watcher, or daemon.

The A1, A2, and A2B maintenance regressions continue to pass.

Live evidence on Maven, 2026-07-27 and 2026-07-28:

- one native password prompt completed both fixed update vectors;
- the reviewed reboot command completed;
- Limine selected the expected kernel and SDDM autologin completed;
- transaction `maintenance_tx_284c81925a26fecf` wrote a boot-bound journal and
  recorded the changed boot identity;
- the first post-login attempt failed closed after 90 seconds because its
  systemd unit lacked Hyprland's instance variables;
- no unsupported application and no absent qBittorrent process was launched;
- after repair, live probes passed Hyprland discovery, the Maven DP-3 recovery
  hook, and one transient user-systemd `/usr/bin/true` launch;
- transaction `maintenance_tx_c81e6cfe1b15e3cc` completed both fixed update
  vectors with one password prompt, invalidated the sudo ticket, rebooted, and
  completed all four restore actions with zero failures;
- DP-1 and DP-3 returned awake at 3440x1440 and 120 Hz;
- Codex returned to workspace 1 on monitor 0 and Opera returned to workspace 2
  on monitor 1; and
- absent qBittorrent and then-unallowlisted Webex/Teams were not launched.

The separate zero-prompt reboot-only transaction
`maintenance_tx_a3fdcd872f2e0ecb` completed on 2026-07-29 with no package
commands, no password prompt, a changed boot identity, display recovery, and
active-workspace restoration. Teams, Vesktop, and Codex restored. Webex and
Opera stopped as two bounded application records: Webex lacked its reviewed
Wayland environment, while Opera rejected a stale singleton lock containing
the former `maven` hostname. The Webex vector is corrected; the three Opera
links were quarantined reversibly and Opera recreated current `atelier` locks.
Winboat, LACT, xfreerdp, and the maintenance terminal remained visibly
unsupported rather than being silently attempted.

## Local LLM eval results

None. Reboot authority, fixed command vectors, journal integrity, application
allowlisting, and persistence are deterministic safety behavior and must not be
delegated to a model.

## Known weaknesses

- The first live post-login attempt exposed and safely recorded compositor
  environment and dispatcher-version incompatibilities. Both are repaired and
  the complete path passed its supervised rerun.
- Exact window placement continues to depend on application class stability
  and compositor timing.
- Individual application launchers can retain their own state or environment
  constraints. Their bounded failure does not invalidate an otherwise
  successful reboot, display recovery, or workspace lifecycle.
- Browser tabs, documents, unsaved work, application-internal state, and
  terminal commands are intentionally not captured or reconstructed.
- Browser session recovery remains the browser's responsibility.
- The restore registry remains conservative and owner-reviewed. Unknown
  applications, games, transient dialogs, and changed executable paths remain
  unsupported.
- Active-work detection covers persisted music jobs, model leases, and the
  backup operation lock. Future long-running subsystems must register before a
  live A3 run is approved.
- Package and Flatpak prompts remain visible human decisions. A3 never answers
  them.
- A failed post-login placement cannot roll the host back to the prior boot; it
  records exact partial evidence for manual recovery.

## Memory keys

None. Maintenance journals and receipts are operational state under the shared
private host-maintenance root, not conversational memory.

## Lifecycle states touched

- `complete`
- `awaiting_input`
- `awaiting_login`
- `failed`
- `canceled`
- `blocked_for_human_review`

No runner or restorer remains silently active after its explicit bound.

## Risk classification

Class 5.

The candidate can request a host reboot only when its separate local gate is
enabled and one exact Dashboard digest is authorized. It cannot update
packages. The public and local default remains disabled. The resume unit has no
privilege or reboot authority.

## Safety and persistence check

```text
Password accepted by Dashboard, Chat, Voice, file, argv, or env: no
Native sudo prompts per A3 transaction: at most one
Shell or model-generated command vector: no
Automatic prompt answers or update retry: no
Reboot command count: at most one
Automatic reboot retry: no
Pending restore journals: at most one
Restore records: at most 32
Per-record restore retry: at most one
Session readiness wait: at most 90 seconds
Persistent process, daemon, timer, watcher, socket, or listener: no
Oneshot unit installed on Maven: yes, exact reviewed definition
Live reboot performed on Maven: yes, two supervised requests
```

## Human review checklist

- [x] Review the exact A3 transaction and reboot vectors.
- [x] Confirm A2 remains a separate non-rebooting operation.
- [x] Confirm `SOUL_MAINTENANCE_A3_LIVE=false` remains effective.
- [x] Review the one-shot unit and exact installation plan.
- [x] Review every restore-registry entry and executable path.
- [x] Confirm unsupported applications and raw process arguments remain
  excluded.
- [x] Install the reviewed one-shot unit through its exact Make target.
- [x] Run a no-journal unit check and inspect status.
- [x] Run an A3 Dashboard preview and exact live transaction.
- [x] Confirm fixed updates, one authentication, reboot, Limine, and autologin.
- [x] Confirm the failed restore was bounded, receipt-backed, and launched
  nothing unsupported.
- [x] Repeat one supervised reboot with repaired Hyprland discovery, typed
  dispatchers, and Maven's bounded DP-3 recovery hook.
- [x] Confirm Codex restores to workspace 1 and Opera to workspace 2 while
  absent qBittorrent remains unlaunched.
- [x] Review Maven's exact Webex and Teams for Linux class/process identities
  and launch vectors.
- [~] The 2026-07-29 reboot proved conditional Teams restoration. Webex was
  present but its internal binary did not create a window without the
  Operator's reviewed Wayland environment; the registry is corrected and will
  be observed during a natural future reboot without blocking A3 acceptance.
- [x] Accept the repaired candidate after supervised evidence.
