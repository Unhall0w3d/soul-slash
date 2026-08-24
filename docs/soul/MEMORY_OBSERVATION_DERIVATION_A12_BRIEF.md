# Memory Observation Derivation A12 Brief

Status: Operator-approved implementation scope, 2026-08-24

## Objective

Bridge immutable conversation observations into bounded, attributable memory
proposals without granting a model lifecycle authority. A12 processes one
foreground observation batch, validates one closed local-model response, and
retains an append-only private proposal packet for a later deterministic
lifecycle policy.

## Authority and lifecycle

- A12 may read exact owner-private conversation observations and send one
  bounded batch to an explicitly local synthesizer.
- A model may propose ordinary candidate memory and evidence relationships. It
  cannot create, approve, promote, demote, supersede, tombstone, delete, or
  rewrite canonical memory.
- Each completed packet records the exact observation range, observation
  digests, input digest, model/Core identity, policy version, proposed layer,
  confidence, evidence IDs, and deterministic protection classification.
- Empty valid results still advance the append-only processing cursor so
  conversational noise is not repeatedly synthesized.
- Invalid output, unavailable local synthesis, changed evidence, path failure,
  or limit failure terminates as `failed` and does not advance the cursor.
- Exact completed input replay is idempotent.

## Bounds and privacy

- One invocation processes at most 24 observations, 12 exchanges, 48 KiB of
  UTF-8 content, and eight proposals.
- Each proposal is at most 1,000 UTF-8 bytes and cites one to eight exact
  observation IDs from the current batch.
- Only local model identities are accepted. No cloud provider, network
  discovery, remote database, or external export is permitted.
- Raw observation content and proposal content remain in ignored owner-private
  files. Public receipts expose counts, IDs, lifecycle state, digests, model
  identity, and protection counts but no content.
- Proposal packets are append-only source material. A later autonomous policy
  consumes them; A12 never writes the canonical memory ledger.

## Protected material

A deterministic classifier marks a proposal `protected_review_required` when
it concerns credentials or secrets, permission or authority grants,
destructive authorization, safety or security policy, operator identity,
protected persona rules, physical purge, external export, retention-policy
changes, or irreversible bulk work. Model labels cannot downgrade this result.
All other proposals remain `ordinary_candidate`; neither class is retrieval
active in A12.

## Execution boundary

- Foreground only; no worker, watcher, timer, service, scheduler, retry loop,
  polling, background continuation, or automatic Core switch.
- The cursor is derived from the newest valid append-only proposal packet; no
  independent mutable checkpoint is authoritative.
- Source observation segments and canonical memory remain unchanged.
- Qdrant, FalkorDB, and Redis are not used in this slice.

## Acceptance

- A bounded batch after the latest completed packet is selected in canonical
  observation order.
- Strict local-model output produces one append-only packet with exact evidence
  provenance and a content-free receipt.
- Evidence outside the selected batch, unsupported fields, invalid UTF-8,
  oversized output, cloud identity, or malformed JSON fails closed.
- Protected material cannot be mislabeled ordinary by model output.
- Empty results advance; failed results do not advance; exact replay is
  idempotent.
- Proposal storage rejects path escape, symlinks, partial writes, tampering,
  duplicate packet IDs, and broken chains.
- Existing observation capture, audit, retrieval, chat, and private-memory
  behavior remains compatible.
