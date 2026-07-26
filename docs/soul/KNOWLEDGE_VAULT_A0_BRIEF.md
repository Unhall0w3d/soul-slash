# Knowledge Vault A0 Brief

## Capability names

`knowledge.vault.status`

`knowledge.vault.search`

`knowledge.vault.initialize`

`knowledge.vault.memory_export`

`knowledge.vault.memory_import`

## Purpose

Add an optional external Markdown knowledge vault that both Soul and a human
can inspect without requiring Obsidian. Obsidian may open the same directory as
a richer editing, linking, properties, and graph surface.

The vault supplements Soul's canonical stores. It must not replace the
append-only conversation-memory ledger, artifact registry, project archives,
or approval history.

## Risk class

- Status and search: Class 0, read-only local.
- Initialization and approved-memory projection: Class 2, local
  non-destructive writes.
- Note-to-memory-candidate import: Class 2, local shared-memory candidate
  write.

## Approved scope

The implementation may:

- Resolve one optional external vault from `SOUL_KNOWLEDGE_VAULT_PATH`.
- Inspect vault readiness without creating it.
- Search bounded regular Markdown files using deterministic lexical ranking.
- Create a reviewed starter structure without overwriting conflicting files.
- Project approved canonical memories into a clearly marked generated
  Markdown index after exact preview approval.
- Import one explicitly selected, bounded Markdown note as a candidate in the
  existing shared memory ledger after exact preview approval.
- Expose typed operations through the existing application facade.
- Provide bounded foreground command-line and Makefile entry points.
- Document optional Obsidian and private-Git-repository use.

## Explicitly out of scope

The implementation must not:

- Require Obsidian.
- Install or configure Obsidian.
- Treat Markdown notes as approved canonical memory.
- Automatically promote imported notes.
- Automatically synchronize, commit, push, pull, or resolve Git conflicts.
- Read credentials, hidden directories, `.git`, or `.obsidian`.
- Follow symlinks.
- Watch the vault or run resident indexing.
- Add services, daemons, scheduled tasks, cron jobs, systemd units,
  background polling, unbounded loops, or continuation after the operation
  returns.
- Send vault content to a cloud provider.

## Inputs

Required configuration:

- `SOUL_KNOWLEDGE_VAULT_PATH`: an absolute path or `~/`-relative path.

Search:

- `query`
- optional `limit`, bounded to 1 through 20

Memory import:

- `relative_path`
- `layer`: `project`, `preference`, `episodic`, or `semantic`

Write execution:

- the exact confirmation phrase returned by preview
- the exact SHA-256 preview digest

## Outputs

User-facing:

- Configuration/readiness status without note content.
- Bounded ranked search results with path, title, and short excerpt.
- Exact write inventories and terminal lifecycle states.
- Candidate memory ID after an approved import.

Structured:

- Application envelopes using the existing lifecycle contract.
- A generated approved-memory index whose canonical source remains the
  conversation-memory ledger.

## Memory behavior

Reads:

- Active approved records from the shared `ConversationMemoryStore` for an
  explicit projection preview or execution.

Writes:

- An explicitly selected vault note may be proposed as one candidate record in
  the shared `ConversationMemoryStore`.

Updates:

- None. Existing memory records are never changed by this slice.

Forget behavior:

- Existing reviewed shared-memory controls remain authoritative.
- Removing a vault note does not delete canonical memory.
- Deleting a candidate or approved memory does not silently rewrite an older
  exported vault projection; a later explicit export refreshes it.

## Task lifecycle

Read operations:

```text
invoked
→ configuration/path validation
→ complete / awaiting_input / failed
→ exit
```

Write operations:

```text
invoked
→ preview
→ blocked_for_human_review
→ exact confirmation and digest validation
→ complete / blocked_for_human_review / failed
→ exit
```

## First-use behavior

If the path is not configured, status reports `awaiting_input` and explains
the required environment key. No default personal directory is guessed.

If the configured directory does not exist, initialization preview reports the
exact directories and files it would create. Search and memory operations do
not create the vault implicitly.

## Provider and dependency behavior

- Ruby standard library only.
- Obsidian is optional.
- Git is optional and remains outside capability execution.
- No network access.
- A single invocation scans at most 500 Markdown files.
- Search reads at most 256 KiB per file and returns at most 20 results.
- Memory import accepts at most 4,000 characters of note body.

## Safety and confirmation gates

- Initialization phrase: `INITIALIZE_KNOWLEDGE_VAULT`
- Memory projection phrase: `EXPORT_APPROVED_MEMORY_TO_VAULT`
- Note import phrase: `IMPORT_VAULT_NOTE_AS_MEMORY_CANDIDATE`
- Every execute operation recomputes its preview and blocks on drift.
- Existing conflicting starter files block initialization rather than being
  overwritten.
- Only the generated approved-memory file may be replaced by projection, and
  only when it retains Soul's generated-file marker.

## Deterministic tests required

- Missing and invalid configuration fail safely.
- Initialization is preview-only until exact confirmation.
- Incorrect confirmation and stale digest create no files.
- Conflicting files and symlinked paths fail closed.
- Hidden directories and non-Markdown files are excluded from search.
- Search limits, file limits, excerpts, and ranking are bounded.
- Export includes approved records only and preserves canonical provenance.
- Import creates a candidate, never an approved record.
- Import rejects traversal, symlinks, oversized notes, unsupported layers, and
  preview drift.
- Application operations are explicitly allowlisted and terminal.
- No watcher, service, scheduler, or network dependency is introduced.

## Local LLM evals

None. This slice is deterministic storage, retrieval, and approval plumbing.
An LLM cannot validate path safety, memory promotion, or write authorization.

## Failure behavior

- Missing configuration: `awaiting_input`.
- Invalid or unsafe path: `failed`.
- Missing vault for read/import/export: `awaiting_input`.
- Confirmation mismatch, digest mismatch, or source drift:
  `blocked_for_human_review`.
- Bounded read/write failure: `failed` with no claimed completion.

## Done criteria

- The configured external vault works without Obsidian.
- Read operations are bounded and do not mutate.
- Every write is preview/digest/confirmation gated.
- Imported notes remain shared-memory candidates.
- Public setup is documented and reproducible.
- Deterministic verification passes.
- A human review artifact is complete.
