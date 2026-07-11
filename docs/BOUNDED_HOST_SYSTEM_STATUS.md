# Bounded Host System Status

Phase 6 provides the read-only `host.system_status` capability.

## Natural-language routing

The host assessment recognizes singular, plural, and compound requests such as:

```text
Can you perform an assessment of your environment?
Can you check the system status?
What filesystems and disks do I have?
List my block devices.
```

Explicit Soul-runtime requests remain separate:

```text
Check Soul runtime status.
```

## Focused follow-ups

Referential follow-ups reuse the latest persisted host evidence:

```text
Which disks were you referring to?
Which filesystems did you mention?
Tell me more about those drives.
```

Storage follow-ups return storage facts rather than repeating memory, network, and service sections.

## Storage presentation

The collector retains structured mount data while human-facing claims:

```text
filter pseudo filesystems
omit zram from physical-disk summaries
group Btrfs subvolume mounts by underlying source
preserve filesystem type, utilization, and mountpoint provenance
```

Example:

```text
Filesystem /dev/nvme0n1p2: btrfs, 1.82 TiB total, 12.0% used; mounted at /, /home, /root.
```

## Provider errors

A request that genuinely reaches the model provider now reports both the error type and message, including the HTTP status when available.

This does not substitute for correct deterministic routing. It merely prevents an opaque `http_error` from masquerading as useful diagnostics.
