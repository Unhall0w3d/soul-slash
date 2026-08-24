# Memory Rebuildable Projection A18 Brief

Status: Operator-approved architecture and contract slice; remote deployment is
not authorized by this brief.

## Objective

Define and verify the disposable projection boundary that will later let Soul
use Qdrant for semantic neighborhoods and FalkorDB for memory relationships.
The canonical append-only conversation-memory ledger remains authoritative.
This slice creates no container, account, credential, listener, firewall rule,
service, timer, scheduled task, or remote mutation.

## Authority and privacy

- Qdrant and FalkorDB are rebuildable indexes, never memory authorities.
- Raw memory text remains on Atelier. Qdrant receives embeddings and bounded
  content-free metadata; search results return canonical memory identifiers for
  a local authoritative join.
- FalkorDB receives bounded content-free lifecycle/provenance nodes and only
  explicit or deterministic relationships.
- Model agreement, vector proximity, and graph proximity are evidence, not
  truth, causality, approval, or mutation authority.
- Projection loss, corruption, staleness, or unavailability causes local
  fallback or a visible unavailable state. It never repairs or rewrites the
  canonical ledger.
- Projection credentials, endpoints, certificates, host identities, and live
  payloads remain owner-private and outside Git.

## Closed projection contract

The contract emits a private in-memory bundle and a content-free public receipt.
It is bounded to 5,000 canonical records and 5,000 approved vector points.

Qdrant points contain:

- deterministic UUID derived from the canonical memory identifier;
- the reviewed embedding vector;
- canonical memory identifier, layer, approved state, source kind, approval
  timestamp, content digest, and canonical source digest.

Qdrant does not receive raw content, source excerpts, chat text, paths, secrets,
or authorization metadata.

FalkorDB nodes contain:

- canonical memory identifier;
- lifecycle state, layer, source kind, created/updated timestamps, content
  digest, and canonical source digest.

FalkorDB edges are limited to:

- `SUPERSEDED_BY`, copied from canonical lifecycle evidence; and
- `EXACT_DUPLICATE`, derived from identical normalized-content digests.

No semantic-similarity, inferred-causality, model-agreement, or speculative
relationship enters the graph in A18.

## Determinism and reconciliation

- Identical canonical state plus identical approved-memory index produces the
  same projection payload digest.
- The public receipt exposes counts, schemas, dimensions, source digests,
  payload digest, freshness state, and authority/fallback labels only.
- A vector index that is absent, stale, malformed, lexical-only, dimensionally
  inconsistent, or based on a different canonical source fails closed.
- Rebuild is replace-by-generation: later deployment writes a new generation,
  verifies counts and digests, then atomically selects it. Partial generations
  are never queried.
- Reconciliation compares the active projection generation to the current
  canonical and approved-index digests. Drift means rebuild, never reverse
  synchronization.

## Later deployment gate

The intended deployment target is one unprivileged autostart Debian LXC on
Foundry. Qdrant and FalkorDB remain private-LAN services behind authenticated
TLS with no public exposure. Exact VMID, address, CPU, RAM, storage, versions,
checksums, credentials, certificates, backup inclusion, firewall rules, health
checks, and rollback belong to a separate reviewed A19 deployment brief and an
exact confirmation/digest gate.

Redis is not required: there is no shared queue, distributed lock, or transient
coordination need at this scale.

## Acceptance

- Synthetic fixtures prove deterministic Qdrant and FalkorDB payloads.
- Raw memory content appears in neither projection payload.
- Only approved records become vector points.
- Deleted and superseded records remain graph-visible but not vector-active.
- Vector dimension and source-digest mismatches fail closed.
- Unknown lifecycle states, layers, relations, malformed identifiers, oversized
  records, and excessive counts fail closed.
- Public receipts contain no vectors, raw content, paths, endpoints, or secrets.
- No network, process, container, persistence, remote host, or live private
  memory is touched by deterministic verification.
