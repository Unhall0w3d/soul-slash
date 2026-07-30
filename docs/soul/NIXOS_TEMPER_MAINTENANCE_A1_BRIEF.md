# NixOS Temper Maintenance A1 Brief

## Objective

Add one reproducible NixOS 26.05 virtual-machine target to the existing
device-scoped maintenance surface so Soul can prove Nix flake update,
generation, and reboot semantics without creating a parallel approval flow.

## Approved scope

- Recognize NixOS through the existing fixed SSH enrollment path.
- Report the native Nix channel only; do not invent APT, AUR, Flatpak, or Snap
  channels when those managers are absent.
- Compare the pinned `nixpkgs` revision with the live stable branch as
  read-only update evidence.
- Treat an active/booted generation mismatch as reboot evidence.
- Install one declarative, root-owned helper exposing only `self-check`,
  `generation-match`, `upgrade`, and `reboot`.
- Route qualified Temper cards through the existing exact-preview,
  device-specific confirmation, operation lock, receipt, reconnect, and
  recollection lifecycle.
- Provide public deployment material without private addresses, credentials,
  host keys, or fleet state.

## Safety boundary

The public default is inventory-only. Control requires an exact authority
self-check plus the ignored local `SOUL_FLEET_TEMPER_CONTROL_ENABLED` setting.
The helper accepts one operation and no forwarded arguments. Upgrade retains
the prior NixOS generation and restores the prior lock file on failure.
Reboot is separate and never automatic. No service, watcher, timer, garbage
collector, background updater, or polling loop is added.

## Acceptance

- NixOS enrolls using immutable `/run/current-system/sw/bin` paths.
- The card exposes exactly one Nix update channel.
- Only exact authority evidence enables control.
- Stale preview evidence executes nothing.
- Maintenance runs one fixed helper invocation.
- Reboot verifies changed boot identity and the three NixOS readiness checks.
- Deterministic verifier and live Temper deployment both pass.
