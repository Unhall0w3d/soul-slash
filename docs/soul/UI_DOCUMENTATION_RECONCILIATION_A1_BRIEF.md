# UI and Documentation Reconciliation A1 Brief

Status: Operator-approved implementation planning; human review required

Date: 2026-07-29

## Objective

Reconcile Soul's current Operator-facing interface, setup guidance, and
authoritative product documentation with behavior already merged on `main`.
Remove stale implementation-phase wording without rewriting historical
engineering evidence or describing candidate work as production.

## Risk classification

Low.

This slice changes explanatory text, generated documentation evidence, and
deterministic drift checks. It must not change runtime behavior, capability
routing, confirmation requirements, model configuration, maintenance
authority, backup semantics, or private state.

## Authoritative active surfaces

The audit may inspect and, after primary-model triage, update:

- `README.md`;
- `docs/CURRENT_STATE.md`;
- `docs/ROADMAP.md`;
- `docs/GETTING_STARTED.md`;
- current Operator guides under `docs/guides/`;
- ordinary Operator-facing labels and help text in the Dashboard;
- Makefile help and public setup defaults where they describe supported
  behavior;
- generated current-inventory documentation and its deterministic verifier.

## Explicit exclusions

The slice must not mechanically rewrite:

- historical phase briefs, maintenance records, assessments, or review
  artifacts;
- exact A1/A2/A3/A4 gate names where the version identifies a real authority
  boundary;
- code identifiers, operation names, confirmation phrases, test fixtures, or
  retained evidence;
- candidate or future language that is still accurate;
- owner-private projects, conversations, proposals, memory, the Knowledge
  Vault, receipts, or Project Timeline history.

A broad search result is evidence to inspect, not permission to replace text.

## Required orchestration

1. A Spark explorer performs a read-only audit and returns a line-specific
   evidence ledger.
2. The primary model classifies every proposed finding as:
   - stale and in scope;
   - accurate current wording;
   - intentionally historical;
   - still candidate/future;
   - blocked by ambiguity or overlapping work.
3. A Spark worker may apply only the approved, bounded correction list.
4. The primary model reviews the actual diff, corrects incomplete work, and
   runs the full verification set.

Spark output is not authority to edit, classify production state, or declare
the slice complete.

## Evidence ledger contract

Each finding must include:

- file and line;
- current claim or label;
- concrete repository evidence;
- proposed disposition;
- affected interface or setup flow;
- uncertainty or overlap, if any.

## Acceptance criteria

- No merged production capability is described as unavailable, merely future,
  or awaiting implementation on an authoritative active surface.
- No candidate, deferred feature, or unreviewed deployment is described as
  live.
- Supported model, runtime, duration, setup, and administration defaults agree
  across current documentation, Dashboard copy, and Makefile help.
- Ordinary Operator-facing labels avoid implementation-phase terminology when
  it adds no authority meaning.
- Exact gate names remain intact where they communicate a real reviewed
  boundary.
- Historical evidence remains historically accurate and unchanged.
- Repository links and generated current-inventory documentation remain valid.
- Deterministic checks fail on the exact reconciled claims without imposing a
  blanket ban on words such as `phase`, `candidate`, or `future`.

## Required verification

At minimum:

```text
make verify-project-timeline
ruby scripts/verify-documentation-registry-refresh-phase38.rb
make supported-stack-check
make verify-maintenance-reboot-restore
node --check assets/dashboard/dashboard.js
git diff --check
```

Additional focused verifiers are required for every Dashboard or setup surface
changed.

## Lifecycle

This bounded repository task terminates as one of:

- `complete`;
- `failed`;
- `awaiting_input`;
- `canceled`;
- `blocked_for_human_review`.

Candidate-complete work stops for Operator review before merge.

## Persistence, memory, and external effects

This slice adds no service, daemon, watcher, scheduled task, network listener,
background loop, credential, model download, package installation, or private
memory key. It performs no external publication and no host or remote-device
mutation.
