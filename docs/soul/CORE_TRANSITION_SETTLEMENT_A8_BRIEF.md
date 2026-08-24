# Core Transition Settlement A8 Brief

Status: human-authorized implementation follow-up on 2026-08-23

## Purpose

Keep the Dashboard truthful during the short observability window after an
explicit Core activation completes. Live A7 acceptance showed that Qwen idle
telemetry and the model-runtime lease can remain briefly unavailable even
though the requested transition has safely completed.

## Boundary

After a successful `core.activate.execute`, the Dashboard may issue at most two
read-only `core.status` requests, after fixed delays of 350 and 1,200
milliseconds. The first complete result is rendered and dependent runtime and
system-status cards are refreshed once.

This reconciliation cannot retry activation, reuse or invent approval, change
a Core, acquire a model lease, relax idle checks, suppress a transition error,
or continue after the foreground interaction returns. If neither read succeeds,
the Core selector reports that status is settling and leaves manual refresh
available.

## Acceptance

- Both Dashboard Core activation paths use the same bounded reconciliation.
- The delay set is exact and contains only two entries.
- No mutation operation occurs in the reconciliation helper.
- Existing Core, memory lifecycle, Dashboard JavaScript, and formatting checks
  pass.
