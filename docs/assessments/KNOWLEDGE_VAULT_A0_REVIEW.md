# Knowledge Vault A0 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Added one optional external Markdown knowledge surface for Soul and the
Operator. Obsidian may open the same directory but is not required. Soul can
report status, perform bounded lexical search, create a reviewed portable
starter structure, project approved canonical memory into a generated note,
and import one selected note into the existing shared memory ledger as a
candidate.

The vault is supplementary. It does not replace canonical memory, Studio
archives, approval records, artifacts, or conversation history.

## Files changed

```text
.env.example
Makefile
README.md
Soul/skills/registry.yaml
docs/ARCHITECTURE.md
docs/ASSISTANT_SKILL_CATALOG.md
docs/CURRENT_STATE.md
docs/GETTING_STARTED.md
docs/guides/KNOWLEDGE_VAULT.md
docs/soul/KNOWLEDGE_VAULT_A0_BRIEF.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/chat_responder.rb
lib/soul_core/configuration_schema.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/knowledge_vault_chat_controls.rb
lib/soul_core/knowledge_vault_service.rb
scripts/soul-knowledge-vault
scripts/verify-knowledge-vault-a0.rb
```

## Commands and deterministic results

```text
ruby scripts/verify-knowledge-vault-a0.rb: pass, 16 checks
ruby -c lib/soul_core/knowledge_vault_service.rb: pass
ruby -c lib/soul_core/knowledge_vault_chat_controls.rb: pass
ruby -c lib/soul_core/chat_responder.rb: pass
git diff --check: pass
```

The verifier covers missing configuration, exact initialization confirmation,
preview drift, starter conflicts, bounded hidden-file-aware search,
approved-only projection, memory-import drift, candidate provenance, traversal,
symlinks, typed application operations, narrow conversational routing, and the
absence of watchers, schedulers, network code, and automatic promotion.

## Local LLM eval

Not run. Storage safety, path handling, digests, and memory promotion cannot be
validated by an LLM. The conversational surface deliberately recognizes only
two explicit read forms and is covered deterministically.

## Memory keys

```text
Reads: active approved records from the shared conversation-memory ledger
Writes: one explicitly selected vault note as a candidate in that same ledger
Updates: none
Automatic approval: none
Forget behavior: existing reviewed shared-memory controls remain authoritative
```

## Task lifecycle states touched

```text
complete
failed
awaiting_input
blocked_for_human_review
```

## Risk classification

- Status and search: Class 0, read-only local.
- Initialization and approved-memory projection: Class 2, local write.
- Note import: Class 2, shared-memory candidate write.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher or resident index added: no
Scheduled task added: no
Network listener or cloud transmission added: no
Automatic Git operation added: no
Automatic memory promotion added: no
Symlink traversal allowed: no
Conflicting starter files overwritten: no
```

## Known weaknesses

- Search is deterministic lexical ranking, not semantic retrieval.
- Each search rescans at most 500 Markdown files; very large vaults need a
  separately reviewed retrieval design.
- Obsidian plugins and proprietary features may create non-portable syntax
  that Soul treats as ordinary text.
- A private Git remote provides access control and history, not end-to-end
  encryption.
- Conversational writes are intentionally absent; mutation uses explicit
  preview/digest/confirmation operations.

## Human review checklist

```text
[ ] Configured personal path is outside the public repository.
[ ] Starter structure is useful when opened in a normal editor.
[ ] Obsidian opens the directory without required plugins.
[ ] Search returns useful bounded excerpts.
[ ] Casual conversation does not trigger Knowledge Vault search.
[ ] Approved-memory projection is clearly marked as generated.
[ ] Imported note remains a candidate until separately approved.
[ ] Private Git remote contains no credentials or unrestricted private data.
```
