# Conversational Soul Phase 9 — Reviewed Memory Controls

Status: implementation slice ready

This slice builds on the Layered Memory Foundation and exposes deterministic, human-reviewed controls for proposing, inspecting, approving, superseding, and logically deleting durable memory.

## Delivered

- bounded conversational memory-command recognition;
- candidate creation from explicit user requests;
- exact provenance with chat identity;
- candidate listing and record inspection;
- explicit approval before context eligibility;
- confirmation-gated supersession;
- confirmation-gated logical deletion;
- model-independent execution;
- regression checks for accidental recall interception;
- append-only audit preservation.

## Deliberately deferred

- automatic model extraction;
- automatic approval or promotion;
- reflection-candidate import;
- bulk export and backup workflows;
- physical purge of ledger history;
- fuzzy mutation against records without exact IDs.
