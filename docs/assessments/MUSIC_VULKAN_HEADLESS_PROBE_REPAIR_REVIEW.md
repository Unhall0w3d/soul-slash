# Music Vulkan Headless-Probe Repair Review

## Candidate

```text
Name: Hardened-dashboard Vulkan inventory repair
Risk class: Class 1 — read-only subprocess environment correction
Date: 2026-07-18
Status: approved and live-verified
```

## Root cause

The host probe enumerated AMD RX 6900 XT and NVIDIA GTX 1070 successfully. Under
the dashboard's systemd hardening, inherited display variables caused an XCB
surface connection failure. The same hardening with `DISPLAY` and
`WAYLAND_DISPLAY` removed enumerated both GPUs and exited successfully.

## Changes

```text
- lib/soul_core/bounded_command_runner.rb
- lib/soul_core/music_resource_coordinator.rb
- scripts/verify-music-vulkan-headless-probe.rb
- docs/soul/MUSIC_VULKAN_HEADLESS_PROBE_REPAIR_BRIEF.md
- docs/assessments/MUSIC_VULKAN_HEADLESS_PROBE_REPAIR_REVIEW.md
```

## Deterministic evidence

```text
ruby scripts/verify-music-vulkan-headless-probe.rb    PASS (3 checks)
ruby scripts/verify-music-studio-a2.rb                PASS (28 checks)
ruby scripts/verify-music-core-vulkan-feasibility.rb  PASS (30 checks)
```

## Memory, lifecycle, and persistence

```text
Memory reads/writes: none
Lifecycle: complete or existing bounded inventory failure
Service/daemon/watcher/schedule/background loop added: no
Confirmation or generation gate weakened: no
```

## Human review checklist

```text
[x] Music Core preview reports AMD Vulkan available
[x] No Core or service transition was required for the repair
[x] Existing Music A2 and Vulkan feasibility regressions pass
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Music Studio preview succeeded after the live dashboard repair.
```
