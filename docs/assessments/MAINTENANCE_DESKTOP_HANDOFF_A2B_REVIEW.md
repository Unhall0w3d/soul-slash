# Maintenance Desktop Handoff A2B Review

Status: candidate-complete; human desktop test required

## What was implemented

- Added a user-local XDG `soul-maintenance://` desktop association that opens
  one reviewed operation in visible kitty.
- Added single-use, digest-bound, owner-private reservations with a ten-minute
  launch deadline, strict URI grammar, atomic claim, and replay rejection.
- Added a native read-only evidence path whose pacman/AUR evidence expires
  after 15 minutes.
- Changed future live A2 execution from a child terminal spawned by the
  Dashboard to a reserved desktop handoff. This preserves
  `NoNewPrivileges=true` on the persistent Dashboard unit.
- Added manual Dashboard controls for refreshing native evidence and receipts.
  There is no polling loop.
- Added exact plan/install/check Makefile targets for the desktop association.
- Kept `SOUL_MAINTENANCE_A2_LIVE=false`; no package update or reboot was
  performed.

## Files changed

- `Makefile`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `config/invocation_catalog.yaml`
- `config/project_tracker_seed.json`
- `docs/CURRENT_STATE.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/MAINTENANCE_DESKTOP_HANDOFF_A2B_BRIEF.md`
- `docs/soul/schemas/maintenance_handoff_reservation.schema.json`
- `docs/soul/schemas/maintenance_native_package_evidence.schema.json`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_capability_guide.rb`
- `lib/soul_core/maintenance_desktop_handoff.rb`
- `lib/soul_core/maintenance_foreground_execution_service.rb`
- `scripts/soul-maintenance-handoff`
- `scripts/soul-maintenance-uri`
- `scripts/verify-maintenance-desktop-handoff-a2b.rb`
- `scripts/verify-maintenance-foreground-execution-a2.rb`
- `docs/assessments/MAINTENANCE_DESKTOP_HANDOFF_A2B_REVIEW.md`

## Deterministic test results

The A2B verifier covers exact desktop-entry recognition, absence of a service
or listener, fixed-argv execution, single-use evidence and transaction URIs,
query-field rejection, owner-private evidence, ten-minute expiry, digest-only
transaction URLs, redacted receipts, replay rejection, zero reboot authority,
timer-free Dashboard behavior, and JSON schema validity.

The existing A2 verifier was updated for reservation semantics and continues to
cover fixed command vectors, no shell, no Dashboard password, one-auth ticket
behavior under injected fixtures, disk/package/active-work gates, disabled
live default, and zero reboot authority.

## Commands run

```text
ruby -c scripts/verify-maintenance-desktop-handoff-a2b.rb
make verify-maintenance-foreground-execution
make verify-maintenance-desktop-handoff
```

## Local LLM eval results

None. URI validation, authentication boundaries, command vectors, replay
protection, and reboot prohibition are deterministic safety behavior.

## Known weaknesses

- The user-local desktop association still needs an exact-plan installation
  and a supervised click test in the operator's ordinary browser.
- Whether that browser displays an external-protocol confirmation is controlled
  by the browser and desktop portal.
- The first supervised test found two desktop-registry defects hidden by
  `xdg-mime`'s textual association: the absolute `Icon=` path was quoted, and
  the non-secret application entry inherited the `0600` mode used for private
  transaction state. Hyprland's generic `xdg-open` additionally treats a
  quoted `Exec=` first token literally and skips the handler. The repair uses
  the fixed metacharacter-free repository executable path as one unquoted
  token, emits a valid unquoted absolute icon path, uses the standard `0644`
  application-metadata mode, and requires both XDG and GIO to resolve the
  reviewed handler before reporting it available. Reservations, evidence, and
  receipts remain `0600`.
- Native package evidence depends on the host's installed `checkupdates`, AUR
  helper, and Flatpak tooling. Failure remains visible and fail-closed.
- Live package execution is still disabled and untested.
- A2B does not reboot, restore applications, answer package prompts, or
  continue after its visible foreground process terminates.

## Memory keys added or used

None.

Owner-private operational state remains under:

```text
Soul/private/host_maintenance/
```

## Task lifecycle states touched

- `complete`
- `failed`
- `blocked_for_human_review`

No handoff waits for human input after returning control. An unused reservation
expires and is pruned on a later bounded invocation.

## Risk classification

Class 5. The handoff is the boundary to a separately disabled privileged
package-update runner. The evidence operation itself is read-only.

## Safety and persistence check

```text
Dashboard service confinement weakened: no
Service, daemon, listener, timer, watcher, or scheduler added: no
Shell parses the URI or command text: no
URI contains a path, command, password, or environment: no
Reservation reusable: no
Reservation launch lifetime: 10 minutes
Native evidence lifetime: 15 minutes
Live update enabled: no
Live update performed: no
Reboot path added: no
```

## Human review checklist

- [ ] Install the exact user-local desktop handler plan.
- [ ] Confirm `make maintenance-handoff-check` reports available.
- [ ] Click **Refresh native evidence** in the ordinary Dashboard browser.
- [ ] Confirm one visible kitty opens, completes read-only checks, and closes.
- [ ] Refresh the A2 preview and confirm native evidence is fresh.
- [ ] Run the no-mutation terminal rehearsal.
- [ ] Confirm the Dashboard service still has `NoNewPrivileges=true`.
- [ ] Confirm live update remains unavailable.
- [ ] Approve, request repair, or reject A2B.
