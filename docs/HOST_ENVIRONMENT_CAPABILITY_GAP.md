# Host Environment Capability Boundaries

Phase 6 implements:

```text
host.system_status
```

## Collected categories

```text
operating system
kernel
uptime
load
memory
mounted filesystems
block-device inventory
network-interface link state
systemd summary
Linux MD RAID arrays visible in /proc/mdstat
```

## Still not collected

```text
SMART health
storage temperatures
hardware RAID controllers
ZFS pool health
firewall policy
authentication logs
scheduled jobs
package update state
external reachability
```

Requests for those deeper categories return an explicit capability boundary.

They are not routed to the general conversation model for invention.

Future extensions should add each category as a separately declared read-only capability with its own collector, provenance, timeout, and regression tests.
