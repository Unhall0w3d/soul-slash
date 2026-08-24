# Memory Core-Aware Worker A17 Brief

## Status

Human-authorized persistence slice. The Operator approved the autonomous-memory
roadmap, always-running improvement bridges that respect Core hot swapping, and
proceeding from live-qualified A16 into this next slice.

## Objective

Deploy an optional systemd user timer that periodically invokes one bounded
foreground A16 lifecycle cycle only when verified pending work exists and the
selected Core can safely provide the local development model.

## Scheduling and Core policy

- Use a systemd user `Type=oneshot` service and timer, not a resident daemon.
- Check ten minutes after boot and fifteen minutes after the prior activation,
  with up to sixty seconds of randomized delay. Missed timers do not catch up.
- Soul Core, Soul-Lite Core, and Dev Core are eligible. The existing reviewed
  Dev orchestrator may temporarily move Soul Core to Soul-Lite, borrow the AMD
  lane, then restore Soul Core.
- Free Core and Creative Core are skipped without mutation. A busy AMD lease is
  a visible terminal failure for that invocation and is reconsidered only by a
  later independent timer activation.
- A no-work check does not invoke a model and does not append an A16 no-work
  cycle, avoiding unbounded idle journal growth.

## Authority and bounds

- Each activation processes at most one derivation packet and one admission
  decision through the already reviewed A16/A13 policy.
- Protected memory remains blocked for human review. Model output has proposal
  authority only.
- Stable request identity derives from the verified pending-work digest, so a
  later activation reconciles interrupted work rather than duplicating it.
- The worker writes one bounded, content-free last-run status receipt. Canonical
  mutation remains recorded in the A10/A13/A16 append-only audit chains.
- Runtime is bounded by the existing local-model timeout plus a 12-minute unit
  timeout. No polling loop, network listener, arbitrary command, or concurrent
  worker is added.

## Deployment gate

The repository may provide plan, install, status, and uninstall commands. The
unit is not installed or enabled until the Operator supplies the exact
`INSTALL_SOUL_MEMORY_LIFECYCLE_TIMER` phrase and the digest from a fresh plan.
Install writes only the two reviewed user units, reloads the user manager, and
enables the timer. Uninstall requires its own exact phrase.

## Acceptance

Deterministic verification must prove no-work model abstention, Free/Creative
skip behavior, eligible-Core execution, stable work-derived request identity,
one-cycle bounds, protected-memory inheritance, content-free bounded status,
exact unit rendering, digest drift rejection, explicit installation and
removal gates, timer cadence, hardening, and no unapproved persistence.
