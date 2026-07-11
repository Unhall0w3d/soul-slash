# Conversational Soul Phase 9 — Layered Memory Foundation

Status: implementation slice

## Purpose

Establish the durable data and retrieval contract for layered memory before exposing conversational mutation controls.

## Delivered

- append-only memory event ledger
- project, preference, episodic, and semantic durable layers
- candidate, approved, superseded, and deleted states
- explicit provenance and confidence
- bounded relevance retrieval
- approved-memory injection into conversation system context
- logical deletion with retained audit events
- no automatic promotion
- Phase 9 assessor and regression verifier

## Deliberately deferred

- user-facing memory proposal and review commands
- automatic candidate generation from conversation
- reflection-to-memory import
- project-specific retrieval indexes
- durable memory backup and export
- approval-gated physical purge

## Acceptance boundary

Phase 9 foundation is ready when:

1. New records remain candidates until approved.
2. Only active approved records enter conversation context.
3. Superseded and deleted records remain auditable but inactive.
4. Provenance and confidence are visible in supplied context.
5. Existing context behavior continues when no project-aware memory store is available.
6. No model call can create or approve durable memory through this implementation.
