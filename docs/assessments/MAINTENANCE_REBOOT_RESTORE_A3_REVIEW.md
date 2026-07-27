# Maintenance Conditional Reboot and Restore A3 Review

Status: candidate-complete; human review and live acceptance required

## Implementation summary

- Added a separately typed and disabled `SOUL_MAINTENANCE_A3_LIVE` gate.
- Added an A3 Dashboard preview that binds the A2 update evidence, restore
  registry, source boot ID, reboot permission, and exact resume-unit state into
  one reviewed digest.
- Extended the existing single-use desktop handoff with a distinct
  `live_reboot` transaction while preserving the non-rebooting A2 path.
- Extended the visible foreground runner to write a durable restore journal
  only after every fixed update command succeeds and all reboot postconditions
  revalidate.
- Added one exact reboot vector:
  `/usr/bin/sudo -n /usr/bin/systemctl reboot`.
- Added one bounded post-login restorer that verifies owner, digest, boot
  change, deadline, restore-registry revision, and retry limits before launching
  or placing an application.
- Added an exact-plan deployment for an owner-level
  `soul-maintenance-resume.service` oneshot unit. Installation enables but never
  starts it.
- Added terminal journal archival and redacted receipts for complete, partial,
  stale, same-boot, and invalid restore outcomes.

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
- package lock, active Soul work, missing resume unit, unavailable reboot
  permission, changed registry, changed boot identity, stale journal, same-boot
  journal, and journal tampering fail closed;
- unsupported applications are never launched;
- already-running background applications are not duplicated;
- partial restoration uses at most one retry and terminates for human review;
- completed restoration consumes the journal and a later unit invocation is a
  no-op;
- installation requires exact confirmation and never starts the resume unit;
  and
- the unit contains no restart policy, timer, listener, watcher, or daemon.

The A1, A2, and A2B maintenance regressions continue to pass.

## Local LLM eval results

None. Reboot authority, fixed command vectors, journal integrity, application
allowlisting, and persistence are deterministic safety behavior and must not be
delegated to a model.

## Known weaknesses

- The one-shot unit has not yet been installed or exercised against a real
  post-login Hyprland session.
- Exact window placement depends on current Hyprland dispatcher behavior and
  application class stability; deterministic adapters cannot prove compositor
  timing.
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

The candidate can update packages and request a host reboot only when its
separate local gate is enabled and one exact Dashboard digest is authorized.
The public and local default remains disabled. The resume unit has no privilege
or reboot authority.

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
Oneshot unit installed during candidate completion: no
Live reboot performed during candidate completion: no
```

## Human review checklist

- [ ] Review the exact A3 transaction and reboot vectors.
- [ ] Confirm A2 remains a separate non-rebooting operation.
- [ ] Confirm `SOUL_MAINTENANCE_A3_LIVE=false` remains effective.
- [ ] Review the one-shot unit and exact installation plan.
- [ ] Review every restore-registry entry and executable path.
- [ ] Confirm unsupported applications and raw process arguments remain
  excluded.
- [ ] Install the reviewed one-shot unit through its exact Make target.
- [ ] Run a no-journal unit check and inspect status.
- [ ] Run an A3 Dashboard preview without arming live execution.
- [ ] Approve, request repair, or reject this candidate.
- [ ] Do not enable or run the first live A3 reboot without a later exact,
  supervised authorization.
