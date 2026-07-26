# Knowledge Reflection A1 Brief

## Capability name

`knowledge.vault.reflect`

## Purpose

Give Soul a deterministic policy boundary for deciding whether a proposed
piece of information belongs in the Knowledge Vault, another canonical store,
the reviewed shared-memory flow, the current conversation only, or nowhere.

When the candidate qualifies for the vault, the capability prepares one exact
new note or full-note update with provenance and waits for human approval
before writing it.

## Risk class

- Classification and duplicate search: Class 0, read-only local.
- Approved note creation or replacement: Class 2, local write to the configured
  external vault.

## Approved scope

The implementation may:

- Classify one explicitly supplied bounded candidate using a deterministic
  knowledge-kind and evidence-status matrix.
- Reject likely credentials or secret-bearing content before preview.
- Search the configured vault for bounded duplicate/conflict candidates.
- Derive one portable Markdown path for a new note.
- Target one explicitly selected existing Markdown note for a reviewed update.
- Render YAML properties, provenance, and a human-readable body.
- Preview the exact destination, prior SHA-256 when applicable, new SHA-256,
  complete Markdown, duplicate candidates, and scope digest.
- Write only after the exact phrase and preview digest are supplied.
- Recompute the full preview during execution and block on drift.
- Expose typed application, command-line, Makefile, and registry surfaces.

## Explicitly out of scope

The capability must not:

- Run automatically after conversations or tasks.
- Watch conversations, the vault, or repository files.
- Use a cloud model.
- Treat a model-selected kind, evidence status, or destination as
  authorization.
- Write raw conversations, raw Studio candidates, transient telemetry,
  credentials, authentication material, or unverified speculation.
- Promote a vault note into approved memory.
- Rewrite Studio archives, shared memory, Self Assessment evidence, or
  conversation history.
- Delete notes.
- Commit, push, pull, or synchronize Git.
- Add a service, daemon, scheduler, resident loop, or background continuation.

## Inputs

- `title`: 3–120 characters.
- `body`: 1–8,000 UTF-8 characters.
- `knowledge_kind`, one of:
  - `project`
  - `decision`
  - `research`
  - `workflow`
  - `lesson`
  - `environment`
  - `preference`
  - `episodic_personal`
  - `studio_candidate`
  - `transient_status`
  - `raw_conversation`
  - `credential`
- `evidence_status`, one of:
  - `operator_confirmed`
  - `repository_documentation`
  - `verified_evidence`
  - `candidate`
  - `unverified`
- `source_reference`: 1–200 characters.
- optional `target_relative_path`: an existing regular Markdown note selected
  for a full-note update.
- optional `tags`: at most 10 simple tags.

## Deterministic destination matrix

- Durable project, decision, research, workflow, lesson, and environment
  knowledge with operator-confirmed, repository, or verified evidence:
  `knowledge_vault`.
- Preference or personal episodic context: `shared_memory_candidate`.
- Studio candidate or candidate-specific generation evidence:
  `studio_archive`.
- Transient status, raw conversation, candidate evidence, or unverified
  claims: `conversation_only`.
- Credential classification or detected secret material: `never_store`.

The capability may explain a recommendation. Only the human-approved execute
operation authorizes a vault write.

## Task lifecycle

```text
explicit invocation
→ validate and classify
→ bounded duplicate search
→ destination recommendation
→ if vault eligible, exact note preview
→ blocked_for_human_review
→ exact phrase + digest
→ recompute and verify drift
→ complete / blocked_for_human_review / failed
→ exit
```

## Confirmation

```text
WRITE_KNOWLEDGE_VAULT_NOTE
```

## Memory behavior

Reads: none from canonical memory.

Writes: none to canonical memory.

Vault notes remain supplementary. A separately invoked A0 note-import gate may
later create a shared-memory candidate.

## Deterministic tests required

- Every kind/evidence combination maps to the intended destination.
- Candidate and unverified evidence cannot write to the vault.
- Likely secrets fail closed as `never_store`.
- Classification mutates nothing.
- Duplicate search is bounded and visible.
- New paths are derived below an allowlisted starter directory.
- Updates require an explicitly selected existing regular Markdown note.
- Traversal, hidden paths, symlinks, invalid UTF-8, and oversize inputs fail.
- Wrong phrase, stale digest, and target drift write nothing.
- Exact approval creates or replaces only the reviewed note.
- No canonical memory, Studio, conversation, Git, watcher, network, or service
  mutation occurs.

## Local LLM eval

None for the policy boundary. A later conversational planner may propose
structured inputs, but deterministic code and human approval remain
authoritative.

## Done criteria

- One explicit candidate receives a truthful destination recommendation.
- Vault-eligible content produces a complete exact preview.
- Non-vault content cannot be written through this capability.
- Exact approved creation and update pass deterministic tests.
- Public setup and Operator flow are documented.
- A human review artifact is complete.
