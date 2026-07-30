# NixOS Temper Maintenance A1 Review

## Candidate summary

Temper is a NixOS 26.05 QEMU VM on Foundry using a pinned flake, key-only SSH,
the QEMU guest agent, and one declarative fixed-operation authority. The
existing fleet and device-control services now recognize NixOS without
changing the shared human gates.

## Files changed

- `lib/soul_core/maintenance_fleet_discovery_service.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `lib/soul_core/maintenance_device_control_service.rb`
- `deploy/nixos/temper/soul-maintenance.nix`
- `deploy/nixos/temper/soul-nixos-maintenance`
- `scripts/verify-nixos-maintenance-a1.rb`
- `Makefile`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/soul/NIXOS_TEMPER_MAINTENANCE_A1_BRIEF.md`
- `docs/assessments/NIXOS_TEMPER_MAINTENANCE_A1_REVIEW.md`

## Deterministic validation

Run:

```text
make verify-nixos-maintenance
make verify-maintenance-fleet-discovery
make verify-maintenance-fleet-status
make verify-maintenance-device-control
```

## Live evidence

- Official NixOS 26.05 minimal ISO checksum matched its published SHA-256.
- Installed and booted NixOS 26.05 on VM 200 (`temper`).
- SSH host key matched evidence obtained independently through the QEMU guest
  channel.
- Password authentication, keyboard-interactive authentication, and root SSH
  login are disabled.
- QEMU guest agent and SSH are active.
- Broad sudo and invalid helper operations are rejected.
- Fixed helper self-check succeeds.
- A bounded helper reboot returned with matching current and booted
  generations.
- The reviewed MAC acquired its reserved final address, its SSH fingerprint
  remained unchanged, and the ordinary digest-bound alias and fleet-enrollment
  gates created the owner-private Temper record.
- Initial post-enrollment live qualification failed closed because refresh
  reachability still tried only `/usr/bin/hostname` and `/bin/hostname`.
  The adapter now includes the immutable NixOS hostname path, with a
  deterministic full-refresh regression before live maintenance was retried.
- The next qualification reached Temper but rejected the unwrapped
  `/run/current-system/sw/bin/sudo` binary. All authority calls now use
  NixOS's setuid `/run/wrappers/bin/sudo`, and the deterministic preview binds
  that exact path.
- The final merged-adapter acceptance exposed a healthy maintenance card,
  zero current Nix source updates, matching active/booted generations, and
  active SSH, QEMU guest agent, and fixed authority evidence. Exact
  `MAINTAIN_TEMPER` execution completed as private receipt
  `device_receipt_180795accefb5a6b` with one fixed upgrade call, no reboot,
  and no automatic retry.

## Local LLM eval

Not applicable. This slice is deterministic fleet inventory and privileged
operation routing; model output cannot validate its safety.

## Known weaknesses

- The native update count represents whether the pinned NixOS source revision
  differs, not a package-by-package count.
- The final LAN reservation, SSH alias, and enrolled record are intentionally
  owner-private local deployment state and are not committed.
- Rollback remains an explicit operator action using retained NixOS
  generations; it is not exposed in A1.

## Memory and lifecycle

No memory keys are added. Existing owner-private fleet registry, snapshot,
operation lock, and receipt storage are reused. Lifecycle states touched are
`complete`, `failed`, `awaiting_input`, and `blocked_for_human_review`.

## Risk

Class 5: remote privileged package/system generation mutation and reboot.

## Human review checklist

- [ ] Confirm public deployment material contains no private addressing or
  key material.
- [ ] Inspect the four fixed helper operations.
- [ ] Confirm stale digest and wrong confirmation execute nothing.
- [ ] Review deterministic verifier output.
- [ ] Review live Dashboard Temper card.
- [ ] Approve or reject merge.
