# Agent Execution Control Plane A0 Brief

## Status and authority

Status: approved implementation scope from the September 21, 2026 operator
review.

This brief introduces deterministic contracts around Codex role isolation and
evidence. It does not change Soul's project-default sandbox mode or authorize
privileged, destructive, persistent, remote, promotion, deployment, merge, or
release actions.

## Objective

Move stable agent safety and evidence properties out of repeated prose and into
small, inspectable configuration and validation surfaces while retaining Astra
as the primary integration and human-review coordinator.

## A0 scope

1. Add project-scoped `mapper`, `implementer`, and `reviewer` role TOMLs.
2. Establish the approved authority and precedence order in global and Soul
   policy.
3. Reconcile the deterministic-testing rule and bounded-job semantics.
4. Add a structured native-subagent assignment schema and validator.
5. Add a universal review-artifact validator.
6. Add a common lifecycle-receipt schema and validator.
7. Add a changed-path to required-check registry and resolver.
8. Add an advisory persistence classifier.
9. Audit actual uses that may depend on `danger-full-access` without changing
   the project default.

The cloud-assistance envelope and a project-default switch to
`workspace-write` are later review gates.

## Authority order

1. Platform and effective sandbox limits.
2. Explicit current user authorization.
3. Non-waivable repository safeguards.
4. Approved task or skill brief.
5. Repository defaults.
6. Selected role TOML.
7. Assignment-specific execution details.
8. Decision heuristics.

A lower layer may narrow authority but cannot expand it. A brief may authorize
an exact service or other normally prohibited capability, but it cannot bypass
destructive confirmation, path, credential, privacy, or human-promotion gates.

## Role boundaries

- `mapper`: read-only evidence collection.
- `implementer`: workspace-write changes limited to explicitly owned paths.
- `reviewer`: read-only correctness, safety, and evidence review.
- Privileged operations remain primary-agent work and require explicit
  escalation.

Role files intentionally omit model and reasoning settings so the primary can
route dynamically without weakening the stable authority boundary.

## Deterministic contracts

The implementation must use only already-available runtime facilities. It must:

- reject malformed or over-broad assignment envelopes;
- require an exact terminal lifecycle state and explicit continuation record;
- validate the canonical review packet headings and enumerated values;
- resolve required checks from an auditable registry without executing them;
- report possible persistence behavior as advisory evidence rather than
  treating a lexical match as authorization or proof;
- reject symlink, non-file, out-of-repository, and oversized inputs.

## Testing rule

Run deterministic checks for every implementation. Add or update tests only
when the change introduces distinct behavior or a credible failure mode not
already covered. Safety-sensitive behavior must have deterministic coverage.

## Acceptance

- All three role TOMLs parse and declare the expected sandbox.
- Valid assignment, lifecycle, and review fixtures pass.
- Missing fields, unknown fields, invalid roles/states, unsafe paths, and
  incomplete continuation evidence fail closed.
- Required-check resolution is deterministic and deduplicated.
- Persistence classification is explicitly advisory and emits source evidence.
- The danger-full-access audit distinguishes development access, privileged
  deployment, hardware access, local sockets, and remote/external networking.
- The review artifact records remaining decisions before any sandbox-default
  change.
