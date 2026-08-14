# Software and Storage Steward A0–A1 Review

Status: candidate-complete; awaiting Operator review

## Implemented

- a bounded foreground Software Steward for pacman, foreign/AUR, orphan,
  Flatpak, and installed-package Arch security evidence;
- a bounded foreground Storage Steward for block devices, filesystems, NVMe,
  and explicitly configured Btrfs compression roots;
- a separately invoked, bounded I/O diagnostic that does not elevate when
  `iotop` is unavailable to the Dashboard process;
- Administration → Host Stewardship cards with manual refresh controls and
  explicit unavailable evidence; and
- portable empty-by-default `SOUL_STORAGE_STEWARD_PATHS` configuration.

## Files changed

The exact candidate diff is the authoritative file list. It includes the two
steward services, application contract/facade wiring, capability registry,
Dashboard markup/styles/client rendering, portable configuration, verifier,
Makefile target, and current documentation.

## Commands and results

```text
make verify-software-storage-steward                 PASS (16 assertions)
make verify-host-stewardship-file-steward            PASS (23 assertions)
node --check assets/dashboard/dashboard.js            PASS
ruby JSON parse config/project_tracker_seed.json      PASS
git diff --check                                      PASS
```

## Local qualification

Atelier currently provides `nvme-cli` 2.16, `iotop-c` 1.31, `compsize`,
`arch-audit` 0.2.0, and pacman 7.1.0. The host uses Btrfs on a Samsung 980 PRO
2 TB NVMe device. `arch-audit --json` returns current public advisory evidence.
Unprivileged `iotop` lacks the required kernel authority in the Dashboard
session and must therefore render unavailable without a sudo prompt or Linux
capability change. NVMe SMART evidence is similarly conditional on existing
unprivileged device access.

The live 2026-08-14 foreground qualification reported 1,625 installed
packages, 14 foreign/AUR packages, 6 orphan candidates, 1 Flatpak application,
and 20 public Arch security findings grouped as 1 unknown, 2 high, 13 medium,
and 4 low. The installed `arch-audit` advisory-per-record JSON shape was caught
during qualification and the parser was corrected to attribute each AVG
record to its actual package list. Live I/O qualification terminated complete
with explicit unavailable evidence because existing unprivileged authority is
absent; it requested no elevation.

## Memory and lifecycle

No memory key is added or used. Every request terminates as `complete` or a
visible failure state. No watcher, scheduler, service, listener, retry loop,
background continuation, or automatic refresh is added.

## Risk classification

Read-only, local-host evidence with one explicitly disclosed optional public
security lookup. The services have no package or storage mutation authority.

## Known weaknesses

- `arch-audit` reports upstream advisory metadata; it does not prove that an
  exploit is reachable in the local configuration.
- Foreign/AUR and orphan status are review signals, not removal advice.
- NVMe health and I/O evidence may be unavailable to the unprivileged
  Dashboard process.
- `compsize` may be unavailable for unsupported filesystems or sandboxed
  mounts; only configured root IDs are exposed.

## Human review checklist

- [ ] Software counts and bounded lists are understandable and accurate.
- [ ] The public security lookup is clear before invocation.
- [ ] No software or storage mutation is offered.
- [ ] Device and filesystem evidence exposes no serial, absolute path, command
      line, environment value, or file content.
- [ ] An unavailable I/O or SMART source remains honest and does not request
      privilege.
- [ ] Manual refreshes remain separate and foreground-only.
- [ ] Responsive Dashboard presentation is acceptable.
