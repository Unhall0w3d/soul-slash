# Software and Storage Steward A0-A1 Brief

status: human-approved
approved_by: Operator
approved_on: 2026-08-14
risk: Class 2 foreground read-only host evidence

## Purpose

Extend Administration -> Host Stewardship with two separately requested,
foreground-only evidence surfaces:

1. **Software Steward A0** — bounded installed-software composition and current
   Arch Linux vulnerability evidence; and
2. **Storage Steward A1** — bounded block-device, mounted-filesystem, NVMe,
   configured Btrfs compression, and optional process-I/O evidence.

This slice interprets evidence. It does not install, update, remove, repair,
quarantine, optimize, trim, rebalance, scrub, format, mount, unmount, or change
software, filesystems, devices, privileges, capabilities, or services.

## Software Steward A0

One explicit foreground refresh may run fixed read-only commands to report:

- installed, explicitly installed native, foreign/AUR, and orphan-candidate
  package counts from pacman;
- bounded foreign/AUR and orphan-candidate package-name lists;
- installed Flatpak application count and bounded application-ID list when
  Flatpak is available; and
- current `arch-audit --json` findings grouped by severity, with bounded
  advisory, affected-package, fixed-version, and CVE evidence.

The Dashboard must state that `arch-audit` may contact the Arch security
tracker during that explicit refresh. An unavailable, timed-out, malformed, or
truncated source remains unavailable and must not be interpreted as clean.

Software Steward has no package mutation authority. Orphan candidates and
foreign packages are inventory evidence, never automatic removal candidates.

## Storage Steward A1

One explicit foreground refresh may run fixed read-only commands to report:

- bounded physical block-device identity without serial numbers;
- bounded mounted-filesystem type, capacity, use, and non-path mount-ID
  evidence;
- NVMe model, firmware, namespace capacity, and current allocation from
  `nvme list` when available;
- NVMe SMART/health fields only when the current unprivileged service context
  can read them; no sudo prompt or privilege adjustment is allowed;
- Btrfs compression evidence from `compsize` only for roots configured through
  `SOUL_STORAGE_STEWARD_PATHS`; and
- an optional, separately requested two-sample `iotop` diagnostic (provided by
  the `iotop-c` package on Arch) only when the current service context already
  has sufficient read authority.

`SOUL_STORAGE_STEWARD_PATHS` uses semicolon-separated `root_id=absolute_path`
entries. The public default is empty. Responses expose root IDs, never the
configured absolute path. Each compression scan is independently limited to
12 seconds and bounded output. A timeout is terminal and leaves no child
process running.

The I/O diagnostic uses fixed batch/process/no-color arguments, a maximum of
two samples, a two-second interval, bounded output, and no command-line
content. If the kernel requires root or `CAP_NET_ADMIN`, the result explains
that the diagnostic is unavailable. This slice must not add sudoers rules or
set file capabilities.

## Shared limits and privacy

- Every command uses a fixed executable and fixed arguments selected by Soul.
- Each command has a timeout and output-byte limit.
- At most 100 package IDs, 100 audit findings, 64 devices, 64 filesystems,
  eight compression roots, and 25 I/O rows may be returned.
- Serial numbers, file contents, process command lines, environment values,
  configured absolute compression paths, and secrets are excluded.
- Evidence is owner-private and ephemeral; no durable inventory or new memory
  store is created.
- No model is required and no evidence is automatically added to model
  context.
- Chat and Voice invocation are outside this slice.

## Lifecycle and persistence

Operations terminate as `complete`, `failed`, `awaiting_input`, `canceled`, or
`blocked_for_human_review`. Partial source availability may produce a complete
snapshot only when every unavailable source is explicitly represented.

This slice adds no service, daemon, watcher, listener, scheduled task, timer,
cron job, background queue, automatic retry, unbounded poll, or continuation
after returning control to the Operator.

## Acceptance

- deterministic fixtures prove command allowlists, bounds, parsing, source
  attribution, and fail-closed malformed/truncated behavior;
- missing `arch-audit`, `nvme`, `compsize`, or `iotop` remains visible rather
  than being interpreted as healthy;
- unprivileged NVMe SMART and `iotop` failures do not request elevation;
- compression roots remain empty by default and never leak absolute paths;
- timeout handling terminates the complete command process group;
- Dashboard refreshes are explicit, live-updating, and do not poll;
- Host Stewardship capability declarations match implemented authority;
- existing File Steward and Storage & Retention boundaries remain unchanged;
  and
- documentation, Project Timeline, and the human-review artifact agree before
  review.
