# Conversational Soul Phase 6 Routing and Output Repair

Manual Phase 6 testing exposed two routing misses:

```text
what filesystems and disks do i have?
which disks were you referring to?
```

Both fell through to the model provider instead of the deterministic host-evidence path.

The same test also showed noisy human-facing storage claims for pseudo filesystems, repeated Btrfs subvolumes, and zram.

## Repair

```text
broaden compound and plural host routing
recognize plural referential follow-ups
focus follow-up output by evidence category
filter pseudo filesystems
group Btrfs subvolume claims
omit zram from disk summaries
preserve complete provider error messages
```

This is Phase 6 hardening and does not add another milestone phase.
