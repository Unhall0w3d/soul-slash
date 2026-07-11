# Changelog

## Unreleased

### Conversational Soul

- Added a generic deterministic evidence follow-up router with evidence-record selection and claim-level focus.

- Hardened Phase 6 host routing, focused evidence follow-ups, storage claim filtering, and provider error detail.

- Completed Phases 1 through 5.
- Began Phase 6 bounded host environment assessment.
- Added the read-only `host.system_status` capability.
- Added bounded collection of OS, kernel, uptime, load, memory, filesystems, block devices, network-interface link state, systemd state, and Linux MD RAID visibility.
- Added structured host evidence with command provenance and explicit uncollected categories.
- Reserved `system.status` for explicit Soul runtime status.
- Routed generic system and environment assessment requests to `host.system_status`.
- Kept host result rendering deterministic in Phase 6.
- Added fixture regression coverage for Btrfs, 12% utilization, and no active Linux MD RAID arrays.
- Preserved Phase 4 and Phase 5 assessor compatibility.

### Development direction

Phase 6 gives Soul real host facts. Phase 7 begins layered memory, now that the assistant has a safer distinction between remembered statements and collected evidence.
