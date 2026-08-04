# Witness Raspberry Pi Maintenance A1 Brief

## Objective

Enroll one Raspberry Pi OS / Debian endpoint as Witness: a passive Wazuh
sensor and a separately gated, device-scoped APT maintenance target.

## Approved scope

- Preserve the existing digest-bound fleet enrollment and literal `witness`
  SSH alias.
- Report live APT simulation, running kernel, reboot marker, SSH, Wazuh agent,
  and fixed-authority evidence.
- Install one root-owned helper exposing only `self-check`, `apt-upgrade`, and
  `reboot`.
- Remove the image-generated broad passwordless sudo rule only after the new
  helper, digest-qualified sudoers policy, syntax check, and self-check pass.
- Route qualified cards through the existing preview, exact confirmation,
  operation lock, receipt, reconnect, and recollection lifecycle.
- Keep private addressing, keys, host keys, fleet records, Wazuh credentials,
  and agent keys in ignored owner-local state.

## Safety boundary

The public default is inventory-only. Control requires an exact address and
SSH-alias match, `SOUL_FLEET_WITNESS_CONTROL_ENABLED`, and a fixed helper
self-check proving that arbitrary forwarding and password storage are absent
and the broad cloud-init sudo rule is gone. The helper accepts exactly one
operation and no forwarded arguments. Reboot remains separate and is never
automatic. Wazuh Active Response is explicitly disabled.

## Acceptance

- The official ARM64 Wazuh agent matches the manager release and remains
  passive.
- Temporary enrollment access closes after registration; only event transport
  remains open from Witness.
- APT evidence never creates authority by itself.
- Broad passwordless sudo is removed only after fixed authority activation.
- Invalid helper operations, stale preview evidence, and arbitrary sudo fail
  closed.
- Maintenance and reboot vectors contain only the fixed helper operations.
- Reboot, when separately approved, verifies reconnect plus SSH, Wazuh, APT,
  and authority readiness before refreshing the card.
