# Bounded Host System Status

Phase 6 adds the first real host-environment assessment capability.

Skill ID:

```text
host.system_status
```

## Scope

The collector performs a bounded read-only Linux assessment.

It may collect:

```text
hostname
operating-system identity
kernel summary
uptime
load averages
memory totals and availability
mounted filesystem type and utilization
block-device inventory
network-interface link state
systemd runtime summary
active Linux MD RAID arrays listed in /proc/mdstat
```

## Commands

Commands are executed as argument arrays, never through an interpolated shell:

```text
uname -srmo
findmnt --json --bytes ...
df -B1 -T ...
lsblk --json --bytes ...
ip -j link show
systemctl is-system-running
systemctl --failed --no-legend --plain
```

Each command has a bounded timeout.

## Files

Read-only files:

```text
/etc/os-release
/proc/uptime
/proc/loadavg
/proc/meminfo
/proc/mdstat
```

## Privacy boundaries

The collector does not collect:

```text
MAC addresses
IP addresses
serial numbers
secrets
authentication logs
firewall rules
scheduled jobs
process command lines
```

## Explicitly not collected

```text
SMART health
device temperatures
hardware RAID controller state
ZFS pool health
firewall policy
authentication logs
scheduled jobs
package update state
external reachability
```

These remain unknown.

## RAID wording

An empty `/proc/mdstat` supports only this claim:

```text
No active Linux MD RAID arrays are listed in /proc/mdstat.
```

It does not prove that no hardware RAID controller, firmware RAID, ZFS pool, or other storage aggregation exists.

## Conversation behavior

Requests such as:

```text
Can you perform an assessment of your environment?
Can you check the system status and tell me what it means?
What filesystems and disks do I have?
```

invoke `host.system_status`.

Phase 6 returns deterministic evidence without model synthesis. This keeps host facts exact while later personality work remains free to be more expressive around safer material.

Follow-up questions reuse persisted evidence from Phase 5.
