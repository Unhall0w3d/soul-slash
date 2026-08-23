# e1000e Hardware-Hang Recovery A0 Brief

## Human authorization

The Operator explicitly approved a continuously running service that reacts to
the reproduced Intel `e1000e` hardware-unit-hang fault by cycling the affected
Ethernet link. This is the narrow persistent-service exception required by the
repository policy.

## Scope

Install the same root-owned recovery service on Forge and Foundry. Both hosts
use the onboard Intel `e1000e` adapter as Proxmox interface `nic0`, and both have
independently produced the exact kernel event:

```text
e1000e 0000:00:1f.6 nic0: Detected Hardware Unit Hang:
```

The service follows new kernel-journal records only. On the first exact event,
it verifies that `nic0` still exists and is driven by `e1000e`, then performs:

```text
ip link set dev nic0 down
sleep 2
ip link set dev nic0 up
```

Further matching events are ignored for 60 seconds. Recovery attempts and
outcomes are retained in the system journal under the
`soul-e1000e-recovery` identifier.

## Authority and safety boundary

- The interface name and driver are fixed; no caller-supplied target exists.
- Only an exact new kernel event can trigger recovery.
- The service cannot forward commands, change addressing, modify bridges,
  reboot a host, or mutate a guest.
- The Proxmox bridge remains configured; only its physical member is cycled.
- A failed attempt to bring the interface back up is logged and causes the
  service to fail visibly rather than silently continuing.
- systemd restart behavior is bounded by start-rate limiting.

## Lifecycle

The service starts at boot and remains active while the host runs. It exits
failed if its prerequisites disappear or recovery cannot restore `nic0`.
Stopping or disabling the unit ends all monitoring. Removing the unit and
helper fully rolls back A0.

## Acceptance

1. Deterministic verification confirms the fixed signature, interface, driver,
   cooldown, link-cycle sequence, and absence of dynamic command execution.
2. Both hosts pass helper validation before installation.
3. The enabled unit is active on Forge and Foundry.
4. Service hardening and journal evidence are reviewable.
5. No synthetic production link interruption is required for acceptance.
