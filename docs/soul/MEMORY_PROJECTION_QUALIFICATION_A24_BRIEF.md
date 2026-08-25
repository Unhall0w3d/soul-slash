# Memory Projection Qualification A24 Brief

Status: implementation candidate. No production routing or threshold is approved.

## Objective

Compare the existing local approved-memory retrieval path with A23 remote
candidate ranking over one fixed owner-private corpus. Measure positive recall,
reciprocal rank, forbidden hits, and negative-case abstention across a closed
threshold sweep.

## Authority and privacy

- The corpus lives only under ignored owner-private memory storage.
- The corpus must be a regular owner-owned file with no group or world access;
  symlinks and path changes during the bounded read fail closed.
- It must include both positive and negative cases and may name only reviewed
  canonical memory identifiers.
- Every corpus and retrieval identifier is revalidated against the current
  approved canonical identifier set before it can contribute evidence.
- Output withholds query and memory content. It exposes case IDs, query digests,
  memory identifiers, and aggregate metrics.
- Projection fallback is not a valid qualification result.
- No threshold, ranking profile, Chat route, or Voice route is selected or
  changed automatically. The result always requires human review.

## Bounds

- Corpus: 2..48 cases and at most 64 KiB.
- Query: one line and at most 200 characters.
- Expected/forbidden identifiers: at most 8 each.
- Results: 1..8 per collaborator.
- Thresholds: exactly 0.50 through 0.80 in 0.05 increments.
- One local and one projection query per case, foreground only.
- Entire qualification: at most 120 seconds by default and never more than 300
  seconds.

No mutation, write-back, remote write, service, timer, retry, Core transition,
automatic winner selection, or ordinary Chat/Voice injection is authorized.
