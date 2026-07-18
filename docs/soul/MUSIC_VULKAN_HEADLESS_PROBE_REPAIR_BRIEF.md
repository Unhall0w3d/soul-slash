# Music Vulkan headless-probe repair brief

Status: owner-approved and live-verified (2026-07-18)

## Objective

Make Music Studio's AMD Vulkan availability check valid inside the hardened
dashboard service. The GPU and driver are healthy; graphical display variables
caused `vulkaninfo --summary` to attempt an unauthorized XCB surface and exit
before Soul accepted the enumerated device.

## Contract

- Run only the existing bounded `vulkaninfo --summary` subprocess.
- Remove `DISPLAY` and `WAYLAND_DISPLAY` from that child process only, making
  the inventory device-only and independent of a graphical session.
- Preserve timeout, output cap, AMD/RADV device matching, Core, service, lease,
  and active-work gates.
- Do not change the dashboard service, device permissions, Vulkan installation,
  model residency, Core selection, or generation authority.
- Add no service, daemon, watcher, timer, polling, or background continuation.

The operation remains a read-only point-in-time resource probe and terminates
with the existing inventory lifecycle.
