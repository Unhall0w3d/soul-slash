# Crucible Maintenance Control D1 Review

## Candidate outcome

Crucible can become a mutable Guided Maintenance target without granting the
Dashboard arbitrary root authority. The candidate adds a separately installed
root-owned helper with three literal operations and routes the existing
device-scoped preview, confirmation, receipt, lock, and reboot lifecycle
through that helper.

The 173-package DNF5 transaction completed through the Dashboard after the
initial candidate pass. The live reboot remains a separate Operator-supervised
Dashboard acceptance.

## Files changed

- `lib/soul_core/crucible_maintenance_authority.rb`
- `lib/soul_core/maintenance_device_control_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `scripts/soul-crucible-maintenance-root`
- `scripts/soul-crucible-maintenance-authority`
- `scripts/verify-crucible-maintenance-control-d1.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- relevant Makefile, guide, current-state, tracker, and regression files

## Exact authority

- Helper: `/usr/local/libexec/soul-crucible-maintenance`
- Operations: `self-check`, `dnf5-upgrade`, `reboot`
- Maintenance vector: `/usr/bin/dnf5 -y upgrade --refresh`
- Reboot vector: `/usr/bin/systemctl reboot`
- Password storage: none
- Request-provided command, path, option, package, or host: none
- Automatic maintenance retry: none
- Automatic reboot after maintenance: none
- Reboot request retry: none

The installer replaces `/etc/sudoers.d/90-cloud-init-users`, which granted
`souladmin NOPASSWD:ALL`, with a digest-pinned exact helper rule. If exact
self-check fails, fleet status exposes no mutation controls.

## Lifecycle states

- Preview: `complete` or `awaiting_input`
- Stale digest / disabled live gate / active lock: `blocked_for_human_review`
- Exact maintenance success: `complete`
- Command failure: `failed`
- Changed boot without readiness: `blocked_for_human_review`

## Memory and persistence

No memory keys are added. Existing owner-private fleet snapshots and redacted
device receipts are reused. The installed helper and sudoers rule are host
policy, not model memory.

## Deterministic verification

Run:

```bash
make verify-crucible-maintenance-control
make verify-crucible-fedora-status
make verify-maintenance-device-control
make verify-maintenance-fleet-status
```

The D1 verifier proves:

- three fixed helper operations and no command forwarding;
- SHA-256-bound sudoers content with no broad authority;
- stale install and device-action digests execute nothing;
- one helper call per maintenance action;
- exact reboot helper and four fixed readiness checks;
- fleet controls appear only after exact authority self-check; and
- separate SSH-integrated and status-only Dashboard surfaces.

All listed deterministic commands passed on 2026-07-28. Live installation
then reported the expected helper digest, no broad cloud-init authority, and
rejected `sudo -n /usr/bin/id` with a password requirement. SSH, the QEMU guest
agent, and `/srv/soul-backup` remained available. The refreshed private fleet
snapshot exposes Crucible as a fixed-maintenance target with 173 updates.

The live Dashboard rendered four SSH-integrated cards and ten independent
status-only cards. The sampled status-only cards remained 130–155 px high with
grid alignment `start`. Maintenance and Reboot previews showed only the exact
helper vectors and reviewed readiness checks. Neither execution gate was used.

## Local LLM eval

Not applicable. This is deterministic privileged orchestration and UI routing;
an LLM cannot validate its safety or authorization.

## Known weaknesses

- DNF5 rollback is not provided.
- A guest update may still require human review of package-manager failure.
- The 173-package update is accepted; the separate reboot remains untested.
- The fixed 45-minute maintenance bound may need review if unusually slow
  mirrors make a legitimate update exceed it.

## Risk classification

Class 5: privileged package mutation and reboot, constrained to one reviewed
device and exact fixed operations.

## Human review checklist

- [x] Confirm Crucible appears under **SSH integrated**.
- [x] Confirm status-only appliances remain compact under **Status only**.
- [x] Inspect Maintenance preview: one fixed helper `dnf5-upgrade`.
- [x] Execute and observe the 173-package transaction.
- [x] Confirm a terminal receipt and refreshed package evidence.
- [ ] Inspect Reboot preview separately.
- [ ] Reboot once and confirm changed boot identity and all four readiness
      checks.
- [ ] Confirm `/srv/soul-backup` remains mounted and backup data is intact.
- [ ] Approve merge only after the supervised acceptance above.

## Live maintenance result

Receipt `device_receipt_de12d9416cc87d61` completed from
2026-07-28 22:29:11-04:00 through 22:31:13-04:00. Its one fixed maintenance
step exited `0`, output remained bounded, and it requested no reboot. Refreshed
DNF5 evidence reports zero remaining updates.

Post-maintenance review found DNF5's reboot JSON remained false even though
kernel `7.1.5-200.fc44.x86_64` was installed while `6.19.10-300.fc44.x86_64`
was running. The candidate now probes the running kernel on every collection
and treats a newer installed kernel as an independent reboot requirement. This
prevents a stale enrollment-time kernel or incomplete DNF5 reboot signal from
presenting a false Healthy state.
