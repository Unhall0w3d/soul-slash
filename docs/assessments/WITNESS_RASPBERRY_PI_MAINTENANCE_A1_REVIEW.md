# Witness Raspberry Pi Maintenance A1 Review

## Candidate summary

Witness is a Raspberry Pi OS / Debian 13 ARM64 endpoint with a stable private
lease, key-only owner administration, and passive Wazuh telemetry. The slice
adds bounded APT evidence and replaces the image's broad passwordless sudo
rule with three digest-qualified helper invocations.

## Files changed

- `lib/soul_core/maintenance_fleet_status_service.rb`
- `lib/soul_core/maintenance_device_control_service.rb`
- `lib/soul_core/witness_maintenance_authority.rb`
- `lib/soul_core/configuration_schema.rb`
- `scripts/soul-witness-maintenance-root`
- `scripts/soul-witness-maintenance-authority`
- `scripts/verify-witness-maintenance-control-a1.rb`
- `.env.example`
- `Makefile`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/guides/SECURITY_MONITORING.md`
- `docs/soul/WITNESS_RASPBERRY_PI_MAINTENANCE_A1_BRIEF.md`
- `docs/assessments/WITNESS_RASPBERRY_PI_MAINTENANCE_A1_REVIEW.md`

## Deterministic validation

Run:

```text
make verify-witness-maintenance-control
make verify-maintenance-fleet-status
make verify-maintenance-device-control
```

## Live evidence

- Host identity is `witness`; the reviewed static lease is owner-local state.
- The maintenance Ed25519 identity authenticates through the literal
  `witness` SSH alias with strict host-key checking.
- Wazuh manager and agent are release 4.14.7; the official ARM64 package
  checksum matched repository metadata.
- The Witness Wazuh agent is active and connected over the permanent endpoint-specific
  event rule. Temporary registration access was removed after enrollment.
- Endpoint Active Response is explicitly disabled and configuration validation
  passed. An initial edit targeted the first unrelated `disabled` element;
  review caught it before acceptance, restored that vendor value, changed only
  Active Response, and revalidated the running connection.
- The existing image-generated broad passwordless sudo rule was retained until
  the replacement authority passed its reviewed install transaction.
- The digest-bound authority installed successfully. Its self-check proves the
  broad cloud-init sudo rule is absent, arbitrary passwordless sudo is denied,
  and only the three fixed helper operations remain available.
- A post-install manager query still reports the Witness agent active. SSH and
  `wazuh-agent` are active on Witness.
- The final Dashboard collection exposes a managed Witness card with complete
  APT evidence, 11 cached-metadata updates, no current reboot marker, and active
  SSH, Wazuh, and fixed-authority readiness.
- Exact local and remote temporary installer script/package files were removed
  after checksum, installation, and connection evidence was retained.

## Known weaknesses

- APT simulation uses current cached package metadata; maintenance refreshes
  metadata inside the fixed upgrade operation.
- The remote reboot path is intentionally not qualified by enrollment alone;
  it requires a separate disruptive live acceptance.
- Private Wazuh mapping, addressing, SSH material, and operational receipts are
  intentionally absent from the repository.

## Risk

Class 5: remote privileged package mutation and reboot. Wazuh remains passive
and has no remediation authority.

## Human review checklist

- [x] Review passive Wazuh enrollment and endpoint-specific firewall state.
- [x] Review exact helper operations and no-forwarding contract.
- [x] Review deterministic verifier output.
- [x] Review and install the digest-bound authority.
- [x] Confirm broad passwordless sudo is absent and arbitrary sudo is denied.
- [x] Review the live maintenance-enabled Witness card.
- [ ] Separately approve and verify a live reboot qualification.
