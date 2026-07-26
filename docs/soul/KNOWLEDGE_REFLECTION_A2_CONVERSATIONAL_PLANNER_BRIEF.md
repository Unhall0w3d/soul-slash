# Knowledge Reflection A2 Conversational Planner Brief

## Capability name

`knowledge.vault.conversation_reflect`

## Purpose

Let the Operator explicitly ask Soul to inspect one bounded local conversation
for reusable knowledge. A configured local model may draft one structured
candidate and explain why it may matter. Deterministic Knowledge Reflection A1
then decides the canonical destination, rejects likely secrets, searches for
duplicates, and prepares an exact note preview when the candidate belongs in
the Knowledge Vault.

Nothing is stored in the vault until the Operator sends the exact candidate ID
and preview digest through the explicit write command.

## Risk class

- Conversation inspection and local-model drafting: Class 0, local read and
  private review-state write.
- Duplicate search and exact preview: Class 0, read-only vault access.
- Exact approved vault write: Class 2, delegated to Knowledge Reflection A1.

## Approved scope

The implementation may:

- Recognize narrow explicit requests to reflect the active conversation for
  durable, reusable, or Knowledge Vault material.
- Read at most 100 bounded messages from that conversation.
- Send only that bounded private transcript to a configured local-only or
  local-network conversation provider.
- Ask the provider for one strict structured candidate containing a title,
  concise body, knowledge kind, simple tags, rationale, and uncertainties.
- Assign provenance from the active conversation in deterministic code.
- Pass the candidate through the existing A1 destination, secret, duplicate,
  path, and digest boundary.
- Persist one owner-private pending workflow record below the existing
  `Soul/reflection/` review substrate.
- Render the candidate, recommendation, duplicate evidence, complete Markdown
  preview, digest, and exact write command in Chat.
- Load the exact pending candidate only when the Operator supplies:

```text
WRITE_KNOWLEDGE_VAULT_NOTE <candidate_id> <preview_digest>
```

- Recompute the A1 preview during execution and fail closed on transcript,
  candidate, vault, or digest drift.

## Explicitly out of scope

The capability must not:

- Run automatically at the end of a conversation or task.
- Infer approval from conversational agreement, model output, or persona text.
- Inspect another conversation.
- Use a cloud provider.
- Send credentials, private files, vault contents, or shared memory to the
  drafting provider.
- Let the model authorize destination, evidence status, a write, or memory
  promotion.
- Write non-vault destinations through the vault gate.
- Approve, import, or modify canonical shared memory.
- Modify Studio archives, conversation history, or repository files.
- Delete vault notes.
- commit, push, pull, or synchronize Git.
- Add a service, daemon, watcher, scheduler, queue, polling loop, or background
  continuation.

## Inputs

### Draft request

- Active `chat_id`.
- Explicit reflection request.
- Up to 100 messages and 64,000 serialized characters.
- One configured local provider.

### Model candidate

- `preserve`: boolean.
- `title`: 3–120 characters.
- `body`: 1–8,000 characters.
- `knowledge_kind`: one A1 knowledge kind.
- `tags`: at most 10 simple tags.
- `rationale`: 1–1,000 characters.
- `uncertainties`: at most 5 strings of up to 500 characters.

The system assigns:

- `evidence_status: operator_confirmed`, because the Operator explicitly chose
  the bounded conversation as the review source;
- `source_reference: conversation:<chat_id>`;
- candidate ID, packet digest, timestamps, and lifecycle.

This assignment permits a preview only. It does not authorize a write.

## Task lifecycle

```text
explicit invocation
→ bounded local transcript
→ local structured draft
→ deterministic A1 classification
→ private pending review record
→ blocked_for_human_review
→ exact candidate ID + digest
→ recompute A1 scope
→ complete / blocked_for_human_review / failed
→ exit
```

If the model recommends no durable preservation, the operation returns
`complete` with no pending candidate and no mutation.

## Memory behavior

Reads: no canonical memory.

Writes: no canonical memory.

Pending JSON is workflow review state, not memory and not authority. Successful
vault notes remain supplementary until a separate reviewed memory-import flow
is invoked.

## Deterministic tests required

- Casual mentions of knowledge, reflection, or the vault do not invoke A2.
- One narrow explicit phrase routes to A2.
- No provider returns `awaiting_input` without mutation.
- Cloud providers are rejected before transcript transmission.
- Transcript size and message count are bounded.
- Invalid, fenced, extra-key, oversize, and secret-bearing model output fails
  closed or routes to `never_store`.
- The model cannot supply provenance, evidence status, destination, digest, or
  authorization fields.
- Non-vault destinations expose no write command.
- Vault-eligible content creates one private pending candidate and exact A1
  preview without writing a note.
- Wrong candidate ID, another chat ID, wrong digest, and target drift write
  nothing.
- Exact approval writes only the reviewed note through A1.
- No canonical memory, Studio, conversation, Git, network listener, watcher,
  scheduler, or background mutation occurs.

## Local LLM eval

The local model may be evaluated for candidate usefulness, concision,
classification suggestions, and uncertainty reporting. It does not validate
secret handling, destination authority, file safety, digest integrity, or
write approval.

## Done criteria

- Explicit Chat reflection produces a useful review-only proposal.
- The correct deterministic destination is visible.
- A complete exact preview is visible only for vault-eligible content.
- Non-vault and never-store candidates cannot reach execution.
- Exact approved execution passes through A1 and detects drift.
- Focused tests and a human review artifact are complete.
