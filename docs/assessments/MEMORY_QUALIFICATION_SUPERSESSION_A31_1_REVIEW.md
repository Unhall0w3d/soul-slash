# Memory Qualification Supersession A31.1 Review

## Reason

A30 correctly superseded exact duplicates, but the private A29 qualification
corpus retained the historical identifiers. Production retrieval remained
healthy while qualification failed because those identifiers were no longer
active approved records.

## Change

- Resolve qualification identifiers through canonical supersession chains at
  runtime instead of rewriting the private reviewed corpus.
- Bound resolution to 64 transitions and fail closed on cycles, excessive
  chains, unknown identifiers, deleted records, or expected/forbidden overlap.
- Keep returned retrieval identifiers constrained to active approved memory.
- Add deterministic coverage proving that a historical expected identifier
  remains valid after canonical supersession.

## Files changed

- `lib/soul_core/memory_production_qualification_service.rb`
- `scripts/soul-memory-production-qualify`
- `scripts/verify-memory-production-qualification-a29.rb`
- `docs/assessments/MEMORY_QUALIFICATION_SUPERSESSION_A31_1_REVIEW.md`

## Validation

- `ruby scripts/verify-memory-production-qualification-a29.rb`
- live `ruby scripts/soul-memory-production-qualify`
- `ruby -c` on changed Ruby files
- `git diff --check`

## Authority and risk

This is read-only identifier reconciliation. It does not mutate the canonical
ledger, qualification corpus, local index, projection, policy, or timer. The
canonical ledger remains authoritative and ambiguous resolution fails closed.
