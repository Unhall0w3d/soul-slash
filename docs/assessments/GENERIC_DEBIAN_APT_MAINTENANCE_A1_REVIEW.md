# Generic Debian APT Maintenance A1 Review

## Candidate

- Reusable fixed Debian APT helper and root installer.
- Fleet evidence promotion from SSH inventory to fixed maintenance only after exact local allowlist and helper qualification.
- Dynamic device-control target derived from the owner-private enrolled device ID.

## Files changed

- `deploy/maintenance/debian-apt/soul-debian-apt-maintenance`
- `deploy/maintenance/debian-apt/install-authority.sh`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `lib/soul_core/maintenance_device_control_service.rb`
- `scripts/verify-generic-debian-apt-maintenance-a1.rb`
- associated brief, review, Makefile, and observability boundary documentation

## Deterministic validation

- [x] `make verify-generic-debian-apt-maintenance`
- [x] `make verify-maintenance-device-control`
- [x] `make verify-maintenance-fleet-status`
- [x] Ruby and Bash syntax checks
- [x] `git diff --check`

## Live review

- [x] key-only non-root SSH succeeds
- [x] fixed helper self-check succeeds
- [x] arbitrary passwordless sudo fails
- [x] fleet card is SSH-integrated with separate Maintain and Reboot actions
- [x] application services remain healthy

## Risk and memory

- Risk: high-impact but narrowly fixed maintenance/reboot authority.
- Memory keys: none.
- Persistent component: existing endpoint SSH service, explicitly approved for full management; no new Soul daemon or scheduler.
- Known weakness: service-specific post-reboot readiness is intentionally limited to SSH, APT, and the fixed authority. Application health remains covered by fleet observability.
