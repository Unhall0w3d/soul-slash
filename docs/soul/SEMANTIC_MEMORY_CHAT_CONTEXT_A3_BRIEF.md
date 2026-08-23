# Semantic Memory Chat Context A3 Brief

Status: human-approved on 2026-08-23

## Purpose

Allow a fresh, compatible approved-memory semantic index to improve recall in
ordinary Soul Chat while preserving `ConversationMemoryStore` as the only
memory authority and preserving the existing lexical context unchanged when
semantic retrieval is unavailable.

## Authority and admission

- The derived index may nominate memory IDs; it cannot supply authoritative
  prompt content.
- Every nominated ID is re-read from the canonical ledger and must still be in
  the active `approved` state.
- Candidate, superseded, deleted, missing, or malformed records are excluded.
- Existing `always_include` and same-conversation approved records are retained
  before semantic additions.
- Results remain bounded by the existing Chat memory-record limit.
- Semantic admission occurs only when retrieval explicitly reports `hybrid`,
  proving a fresh compatible index and a working configured embedding client.
- Indexed-lexical, lexical-fallback, stale, invalid, unavailable, and failed
  retrieval return the existing lexical context unchanged.

## Runtime boundary

This slice does not install, start, enable, schedule, or keep alive an embedding
runtime. It does not rebuild an index automatically, download a model, switch a
Core, mutate memory, or add background continuation. A separately reviewed
loopback embedding endpoint and an explicit foreground index rebuild are
required before semantic Chat admission becomes active.

## Deterministic acceptance

- a paraphrased semantic match enters the ordinary Chat system prompt;
- canonical ledger content replaces any derived excerpt;
- always-include and same-chat records remain preferred;
- non-approved records cannot enter context even when their IDs are returned;
- an invalid mode or retrieval failure returns the legacy context exactly;
- context is bounded and retrieval creates no memory events;
- existing Memory Observatory and Phase 9 memory regressions pass.

Passing checks produces a candidate for human review and does not authorize a
persistent embedding service or automatic index lifecycle.
