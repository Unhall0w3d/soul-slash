# Memory Projection Hybrid Qualification A25 Brief

Status: implementation candidate. No ranking profile, production route, Chat
route, or Voice route is approved.

## Objective

Consume one completed, content-free A24 qualification envelope and compare three
closed profiles at the fixed projection threshold `0.65`:

1. projection baseline, preserving projection order;
2. `projection_gate_local_order_a25`, retaining only projection-gated IDs and
   ordering those IDs by local retrieval rank; and
3. `projection_gate_weighted_rrf_a25`, using fixed local-dominant
   weights (`0.70` local, `0.30` projection) and `k = 60`.

The A25 service is deterministic and emits candidate evidence for human review.
It does not select or activate a winner.

## Authority and privacy

- The only input is the exact completed
  `soul.memory_projection_qualification.a24.v1` envelope.
- A24 query text and memory content are never accepted or emitted. Case IDs,
  SHA-256 query digests, approved opaque IDs, ordering, and numeric metrics are
  sufficient for this rank-only qualification.
- A24 mutation, selection, fallback, or content-bearing signals fail closed.
- No production profile, Chat route, Voice route, memory record, or projection
  store is changed.

## Bounds and lifecycle

- The envelope is a regular owner-private file under the reviewed private
  memory root, with no symlink path components and at most 512 KiB, or an already
  supplied in-memory envelope for deterministic callers.
- The A24 corpus is limited to 2..48 cases and at most 8 IDs per expected,
  forbidden, or returned list. IDs and case IDs are bounded and revalidated.
- The result is `complete` only for exact schema-valid input; malformed input is
  `failed` with `mutation: none`.
- The operation is foreground and bounded by the A24 case limit. It has no
  persistence, network, retry, service, timer, or background behavior.
