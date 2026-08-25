# Memory Projection Reconciliation A21 Brief

Status: implementation candidate. No live canonical-memory read, projection
write, generation activation, or remote cleanup is authorized by this brief.

## Objective

Define the bounded generation transaction that will populate the deployed
Qdrant and FalkorDB services from the canonical local memory ledger and its
reviewed embedding index without making either projection authoritative.

## Transaction boundary

One foreground invocation:

1. builds the already-reviewed A18 content-free projection bundle;
2. derives immutable generation-specific Qdrant collection and FalkorDB graph
   names from the bundle digest;
3. stages or resumes that exact generation in both stores;
4. verifies dimensions, membership counts, source digests, and payload digest;
5. atomically replaces one owner-private local active-generation selector; and
6. returns a content-free receipt.

Qdrant and FalkorDB do not share a database transaction. Activation therefore
occurs only in the local selector after both independently verify. Future
readers must resolve both generation names from that selector and must never
infer the active graph or collection from newest timestamps or database state.

## Failure and rollback

- Failure before selector replacement leaves the prior selector unchanged.
- A generation created by the failing invocation is eligible for bounded
  best-effort cleanup by its exact derived name only.
- A pre-existing matching generation is never deleted during compensation.
- The prior verified generation remains retained after activation.
- Selecting a previous retained generation is a separate digest-bound rollback
  operation and is not implemented in A21.
- Projection failure always falls back to local authoritative retrieval.

## Privacy and authority

- Raw memory text remains on Atelier.
- Qdrant receives vectors and the A18 bounded content-free metadata.
- FalkorDB receives A18 lifecycle/provenance nodes and explicit relationships.
- Preview and public receipts contain no content, vectors, credentials, private
  paths, private addresses, or database responses.
- Projection output cannot mutate, approve, demote, supersede, rewrite, or
  delete canonical memory.

## Bounds

- At most 5,000 canonical records and 1,024 vector dimensions.
- One generation per foreground invocation.
- Fixed client timeouts and bounded batches belong to the later transport
  adapter.
- No daemon, timer, watcher, retry loop, Core switch, or background continuation
  is introduced.

## A21 implementation boundary

A21 implements the deterministic transaction coordinator over injected clients
and an injected selector store. Tests use synthetic data and perform no network,
service, process, private-memory, or persistent host operations. A later A22
transport/live gate must implement and independently verify the actual TLS
clients before any projection is populated.

## Acceptance

- Preview is digest-bound and contains counts/digests only.
- Stale confirmation or canonical/index drift executes no client mutation.
- Both stores must verify before selector activation.
- Partial creation compensates only exact resources created by that invocation.
- Existing matching generations are resumable and never compensation-deleted.
- Selector failure leaves the previous selector active.
- Identical canonical/index input produces identical names and plan digest.
- All failure receipts remain content-free and select local fallback.
