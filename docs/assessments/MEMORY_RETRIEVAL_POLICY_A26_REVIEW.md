# Memory Retrieval Policy A26 Review

Status: candidate-complete; the distinct A29 production policy is active and
the immutable A25 policy is retained as its rollback target.

## Implemented

- Closed local and projection-gated retrieval profiles.
- Owner-private atomic selector with safe local default.
- Exact preview/confirmation/digest activation and rollback.
- Content-free bounded audit history and retained previous policy.

## Deterministic validation

Run `ruby scripts/verify-memory-retrieval-policy-a26.rb`.

## Human review

- [x] Preserve `projection_gate_local_order_a25` at its historical `0.65` value.
- [x] Activate `projection_gate_local_order_a29` at the production-qualified
  `0.55` threshold.
- [x] Verify status, bounded audit evidence, and retained rollback target.
- [x] Verify deterministic rollback behavior without changing the live policy.
- [x] Do not infer that activation alone routes Chat or Voice.
