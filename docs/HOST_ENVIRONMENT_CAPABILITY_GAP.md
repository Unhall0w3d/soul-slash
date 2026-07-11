# Host Environment Capability Gap

Soul does not yet have a registered host-environment assessment skill.

## Current capability

```text
system.status
```

Scope:

```text
Soul application and registered-runtime status only
```

## Missing capability

Planned:

```text
host.system_status
```

A bounded host assessment should deliberately collect:

```text
kernel and operating system
uptime and load
CPU summary
memory summary
mounted filesystems
filesystem type and usage
block-device layout
network-interface state
selected service state
```

Optional checks such as SMART, firewall policy, RAID, temperatures, and logs must be individually declared and permission-bounded.

## Current response

Requests such as:

```text
assess your environment
check my hardware
what disks do I have
inspect RAID health
```

return an explicit capability-gap response.

They do not go to the general conversation model for improvisation.

## Next phase

Conversational Soul Phase 6 will implement the bounded `host.system_status` read-only capability before the milestone proceeds to durable layered memory.
