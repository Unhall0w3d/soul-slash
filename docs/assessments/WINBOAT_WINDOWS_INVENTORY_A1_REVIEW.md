# WinBoat Windows Inventory A1 Review

## Result

Candidate-complete for live Dashboard acceptance.

## Deterministic evidence

`make verify-winboat-inventory` proves:

- only fixed Docker inspect fields and two fixed port resolutions are used;
- container environment data is never requested;
- the configured container name, FQDN, and private guest address are validated;
- only resolved loopback ports within the reviewed WinBoat ranges are probed;
- a wildcard/non-loopback binding fails closed and receives no connection
  probe;
- a missing container returns bounded unavailable evidence;
- Chancery remains `inventory_only`, host-local, and mutation-disabled; and
- the Dashboard labels the private identity without adding lifecycle actions.

The existing `make verify-maintenance-fleet-status` regression suite also
passes.

## Live read-only evidence

On 2026-08-02 the adapter inspected the existing running WinBoat deployment
without changing it. It confirmed the configured fixed guest identity, the
isolated Docker-side address, loopback-only publication, an active container,
and reachable RDP and WinBoat guest-service bindings. No container environment,
credential, log, guest command, or Windows content was read or retained.

## Remaining acceptance

After the code is deployed and ignored local configuration is enabled, collect
fleet status and confirm that the Chancery card and host-local topology
relationship are readable in the normal Dashboard. This visual review does not
expand A1 into maintenance, reboot, DNS, or LAN authority.
