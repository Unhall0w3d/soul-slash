# Memory Lifecycle Admission A13 Review

## Candidate

Deterministic foreground admission of verified A12 proposals into the canonical audited memory ledger.

## Files

- `lib/soul_core/memory_lifecycle_admission_service.rb`
- `lib/soul_core/memory_protection_policy.rb`
- A12 derivation and A11 observation-store reader extensions
- deterministic verifier, Make target, brief, and this review

## Lifecycle and risk

- States: `complete`, `failed`, and per-proposal `blocked_for_human_review`
- Risk: medium; ordinary canonical memory mutation, audited and reversible
- Persistent/background behavior, network, external database, or model authority: none

## Known boundaries

Conflict consolidation, supersession, deletion, Qdrant/FalkorDB projection,
background scheduling, and Core switching remain later reviewed slices. An
unrelated existing candidate is not promoted automatically.

## Human checklist

- Confirm the 0.70 candidate, 0.90 ordinary activation, and 0.95 semantic activation thresholds.
- Confirm protected content and assistant-only evidence remain excluded.
- Confirm the content-free audit receipt is sufficient for operator review.
