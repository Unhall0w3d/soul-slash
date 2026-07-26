# Knowledge Reflection A1 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Added a deterministic destination policy for proposed durable knowledge. One
explicit bounded candidate is classified as Knowledge Vault, shared-memory
candidate, Studio archive, conversation-only, or never-store. Vault-eligible
content receives duplicate evidence and one exact new-note or full-note-update
preview. No note is written until the exact phrase and scope digest are
supplied and recomputed.

The slice does not autonomously inspect conversations and does not use a model.
It is the authority boundary a later conversational reflection planner must
call.

## Files changed

```text
Makefile
Soul/skills/registry.yaml
config/knowledge_reflection.example.json
docs/ARCHITECTURE.md
docs/ASSISTANT_SKILL_CATALOG.md
docs/CURRENT_STATE.md
docs/GETTING_STARTED.md
docs/assessments/KNOWLEDGE_REFLECTION_A1_REVIEW.md
docs/guides/KNOWLEDGE_VAULT.md
docs/soul/KNOWLEDGE_REFLECTION_A1_BRIEF.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/knowledge_vault_service.rb
scripts/soul-knowledge-vault
scripts/verify-knowledge-vault-a0.rb
```

## Commands and deterministic results

```text
ruby scripts/verify-knowledge-vault-a0.rb: pass, 24 checks
make verify-knowledge-vault: pass, 24 checks
ruby -c lib/soul_core/knowledge_vault_service.rb: pass
ruby -c scripts/soul-knowledge-vault: pass
ruby bin/soul config validate: pass
two identical live previews produce the same digest: pass
git diff --check: pass
```

The broader `verify-phase12b-in-process-application-api.rb` aggregate was also
run. Its direct Phase 12B contract checks passed, including the typed
application surface touched here. The aggregate exits nonzero because its
nested repository-curation regression treats unrelated untracked review
candidate files in the intentionally dirty working tree as a failure. No A1
assertion failed.

## Local LLM eval

Not run. A model cannot validate secret rejection, path safety, canonical
destination policy, digest integrity, or write authorization. No
model-generated classification path is included in A1.

## Memory keys

```text
Reads: none
Writes: none
Automatic promotion: none
```

Preference and personal episodic classifications recommend the existing
shared-memory candidate flow but do not invoke it.

## Lifecycle states touched

```text
complete
failed
awaiting_input
blocked_for_human_review
```

## Risk classification

- Classification and duplicate search: Class 0.
- Exact approved note creation or replacement: Class 2.

## Safety and persistence check

```text
Automatic conversation reflection: no
Persistent service or watcher: no
Background continuation: no
Cloud provider use: no
Canonical memory mutation: no
Studio mutation: no
Conversation mutation: no
Git mutation: no
Note deletion: no
Wrong destination allowed to write: no
Likely secret material allowed to write: no
```

## Known weaknesses

- A1 requires structured candidate inputs; it does not yet interpret an entire
  conversation into those inputs.
- Secret detection is deliberately conservative but cannot recognize every
  possible sensitive fact.
- Duplicate detection is bounded lexical ranking rather than semantic
  equivalence.
- Approved updates replace the complete selected note. The preview must be
  reviewed carefully because A1 does not merge paragraphs.
- Git synchronization remains a separate explicit human operation.

## Human review checklist

```text
[ ] Destination explanations are understandable.
[ ] Preference and transient examples do not offer a vault-write gate.
[ ] Secret-like input produces never-store.
[ ] Duplicate candidates are useful.
[ ] New-note path is appropriate.
[ ] Existing-note replacement shows prior and new hashes.
[ ] Wrong phrase and changed input fail safely.
[ ] Exact approved note is readable in Obsidian.
```
