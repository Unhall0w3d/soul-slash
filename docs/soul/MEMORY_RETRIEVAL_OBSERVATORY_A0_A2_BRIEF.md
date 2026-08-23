# Memory Retrieval and Observatory A0-A2 Brief

Status: human-approved direction on 2026-08-23

## Purpose

Improve Soul's ability to find already-approved durable memory when the
Operator's wording differs from the stored wording, while preserving the
append-only reviewed memory ledger as the only canonical memory authority.

The work adapts useful retrieval and observability concepts evaluated from
Mnemosyne. It does not adopt Mnemosyne's automatic capture, background
consolidation, mutable memory authority, or hard-delete behavior.

## Risk class

Class 1: owner-private read and rebuildable derived state.

No stage grants a model, embedding runtime, index, or Dashboard view authority
to create, approve, supersede, delete, or physically purge durable memory.

## Canonical authority

`ConversationMemoryStore` remains authoritative. Only active `approved`
records are eligible for indexing or retrieval. Candidate, superseded, and
deleted records must never enter the derived index or model context.

The retrieval index is:

- owner-private;
- disposable and exactly rebuildable from the approved ledger;
- source-digest bound;
- never a second memory store;
- never committed to Git;
- ignored when absent, invalid, stale, or built with a different embedding
  profile.

When the index is unavailable or stale, normal approved-only lexical retrieval
must continue without semantic claims.

## A0 - controlled evaluation

A0 provides a reproducible, synthetic acceptance corpus covering:

- exact lexical matches;
- synonyms and paraphrases;
- renamed projects or concepts;
- temporal and supersession wording;
- preferences;
- deliberately absent answers;
- conflicting but differently approved facts;
- unrelated distractors.

The harness compares the existing lexical ranker with hybrid retrieval. It
reports recall, precision, reciprocal rank, abstention, latency, and per-query
evidence. Synthetic deterministic vectors verify ranking and safety mechanics;
a separate explicit live run may use a reviewed local embedding profile.

An A0 result may recommend A1, but benchmark output cannot approve memory,
select a production model, or alter runtime configuration.

## A1 - derived approved-memory index

A1 may add one bounded foreground rebuild and one read-only query path.

The production candidate uses a compact JSON index because Soul's current
approved-memory scale does not justify another database service. Each entry
contains only:

- memory ID and layer;
- content required for retrieval;
- approved source/provenance fields;
- confidence and approved timestamp metadata;
- normalized lexical terms;
- an optional fixed-dimension local embedding.

The index envelope records schema, source digest, embedding profile, dimension,
entry count, generated time, and a digest over the canonical payload.

Embedding requests are permitted only to an explicitly configured loopback
HTTP endpoint. They must have bounded input, batch size, response size,
connection timeout, read timeout, and dimensions. No API key, remote endpoint,
automatic model download, automatic Core switch, or provider fallback is
allowed.

Hybrid ranking must remain explainable. Each result reports bounded lexical,
semantic, confidence, and layer components plus its final score. A minimum
admission threshold preserves honest abstention.

The rebuild lifecycle is:

```text
explicit rebuild request
-> validate approved records and local embedding profile
-> create complete index in a temporary file
-> verify schema, counts, dimensions, source digest, and payload digest
-> atomically replace the prior derived index
-> complete / failed / canceled
-> exit
```

No partial index may replace the last valid index.

## A2 - Memory Observatory

A2 adds a read-only nested Administration surface. It may display:

- counts by memory state, layer, and source;
- recent append-only lifecycle events;
- approved-memory index availability, freshness, source digest, profile, and
  last rebuild time;
- an explicit diagnostic query with ranked result excerpts and a `why recalled`
  score breakdown;
- possible exact-content duplicates and explicit supersession links;
- documented links to the existing Chat memory review commands.

The initial Observatory does not add direct mutation buttons. Existing reviewed
Chat controls remain the sole memory mutation surface until a separate brief
defines digest-bound Dashboard review actions.

All rendered content must use safe text nodes. The response is owner-private,
bounded, authenticated, CSRF-protected, and declares mutation `none`.

## Bounds

- at most 10,000 materialized ledger records inspected;
- at most 5,000 active approved records indexed;
- at most 8,000 characters per indexed record;
- at most 64 embedding inputs per local batch;
- at most 1,024 embedding dimensions;
- at most 20 query results;
- at most 100 lifecycle events returned to the Dashboard;
- one foreground retry is permitted only for a transient local embedding
  request failure;
- no watcher, scheduler, daemon, resident indexer, background thread, network
  listener, unbounded loop, or post-return continuation.

## Privacy and trust

- The public repository contains only synthetic fixtures and neutral examples.
- Private memory content, embeddings, index files, paths, hostnames, and model
  locations remain outside Git.
- Retrieved memory remains context, not authorization.
- Embeddings are sensitive derived data and receive the same owner-private
  treatment as their source text.
- The Observatory must not claim that similarity proves truth, causality, or
  approval beyond the ledger status it actually read.

## Out of scope

- automatic conversation ingestion;
- automatic memory proposal or approval;
- background consolidation or decay;
- a knowledge graph that invents relationships;
- physical purge;
- synchronization to another device or cloud;
- external embedding APIs;
- arbitrary filesystem indexing;
- indexing Knowledge Vault, Studio, or conversation data as canonical memory;
- changing existing memory confirmation gates;
- installing or enabling a persistent embedding service.

## Deterministic acceptance

- only active approved records enter an index fixture;
- stale, malformed, symlinked, dimension-mismatched, or digest-invalid indexes
  fail closed to lexical retrieval;
- index replacement is atomic and leaves a prior valid index intact on failure;
- hybrid results expose their score components and source memory IDs;
- absent-answer fixtures abstain;
- deterministic evaluation demonstrates a semantic-recall gain without a
  precision or authority-boundary regression;
- Dashboard output is bounded, authenticated through existing transport, and
  read-only;
- existing Phase 9 memory, Knowledge Vault, Local Search, Chat intent, and
  Dashboard navigation regressions pass;
- no private runtime artifact appears in Git.

## Human review

Passing checks produces a candidate. Human review must still decide whether
the live local embedding profile improves real Soul queries enough to justify
its runtime and storage cost. Merge does not authorize automatic indexing,
automatic memory admission, or a persistent embedding runtime.
