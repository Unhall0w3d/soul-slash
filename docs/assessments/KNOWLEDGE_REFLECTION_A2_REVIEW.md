# Knowledge Reflection A2 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Added one narrow Chat invocation that asks the configured local conversation
model to draft at most one reusable-knowledge candidate from the active bounded
transcript. The model receives no vault files, canonical memory, credentials,
or authority fields.

Deterministic A1 policy remains authoritative. Secret-like material is rejected
without persistence. Preferences, Studio evidence, transient state, and other
non-vault destinations create no isolated pending store. A vault-eligible
candidate creates one owner-private workflow record containing the exact
Markdown preview, duplicate evidence, and digest. Only
`WRITE_KNOWLEDGE_VAULT_NOTE <candidate_id> <preview_digest>` from the same
conversation can invoke the A1 write gate.

## Files changed

```text
.gitignore
Makefile
Soul/skills/registry.yaml
docs/ARCHITECTURE.md
docs/ASSISTANT_SKILL_CATALOG.md
docs/CURRENT_STATE.md
docs/GETTING_STARTED.md
docs/assessments/KNOWLEDGE_REFLECTION_A2_REVIEW.md
docs/guides/KNOWLEDGE_VAULT.md
docs/soul/KNOWLEDGE_REFLECTION_A2_CONVERSATIONAL_PLANNER_BRIEF.md
lib/soul_core/conversation_knowledge_reflection_service.rb
lib/soul_core/conversation_orchestration_contract.rb
lib/soul_core/conversation_orchestrator.rb
lib/soul_core/conversation_runtime.rb
scripts/verify-knowledge-reflection-a2.rb
```

## Commands and deterministic results

```text
ruby scripts/verify-knowledge-reflection-a2.rb: pass, 17 checks
make verify-knowledge-reflection: pass, 17 checks
ruby scripts/verify-knowledge-vault-a0.rb: pass, 24 checks
ruby -c lib/soul_core/conversation_knowledge_reflection_service.rb: pass
ruby -c lib/soul_core/conversation_orchestrator.rb: pass
ruby -c lib/soul_core/conversation_runtime.rb: pass
ruby bin/soul config validate: pass
git diff --check: pass
```

`scripts/verify-responsive-chat-and-web-research.rb` was also run. Every
orchestrator, research-reflection, grounding, and authenticated-stream
assertion reached before its disconnect fixture passed. The script then exits
nonzero because the existing fixture does not catch the current
`DashboardServer::ClientDisconnected` wrapper after deliberately raising
`EPIPE`; that failure is outside A2 and no knowledge-reflection assertion
failed.

## Local LLM eval

Not run in the deterministic suite. The actual configured local model may be
used during human review to judge candidate usefulness, concision, and
uncertainty reporting. It cannot validate destination authority, secret
handling, path safety, digest integrity, or write approval.

## Memory keys

```text
Reads: none
Writes: none
Automatic promotion: none
```

Pending JSON is bounded workflow review state below the existing
`Soul/reflection/` substrate, not canonical memory. Non-vault candidates do not
create pending files. The pending directory is explicitly excluded from Git so
private reflection candidates remain local.

## Lifecycle states touched

```text
complete
failed
awaiting_input
blocked_for_human_review
```

## Risk classification

- Explicit transcript reflection and destination preview: Class 0.
- Private pending review record: Class 1.
- Exact approved vault note write delegated to A1: Class 2.

## Safety and persistence check

```text
Automatic conversation reflection: no
Cloud transcript transmission: no
Persistent service or watcher: no
Background continuation: no
Canonical memory mutation: no
Studio mutation: no
Conversation-history mutation by the service: no
Git mutation: no
Secret-bearing pending candidate: no
Non-vault isolated candidate store: no
Model-selected authorization: no
```

## Known weaknesses

- A2 proposes at most one candidate per explicit invocation.
- The draft is only as useful as the configured local model, though its output
  remains fully reviewable and non-authorizing.
- Bounded lexical duplicate ranking is not semantic equivalence.
- The initial slice uses an exact text command rather than a dashboard action
  button.
- A2 does not autonomously suggest reflection at conversational stopping
  points. That restraint is intentional; proactive suggestions require a
  separate conversational policy review.
- Pending candidates are retained for human review and are not yet exposed
  through a dedicated list/cancel surface.

## Human review checklist

```text
[ ] Casual discussion does not invoke reflection.
[ ] The explicit phrase drafts one useful candidate.
[ ] The model stays concise and reports uncertainty honestly.
[ ] Secret-like content is rejected without a pending file.
[ ] Preference and Studio examples route away from the vault.
[ ] Duplicate candidates and proposed Markdown are understandable.
[ ] Wrong digest and another conversation fail safely.
[ ] Exact command writes the reviewed note once.
[ ] The written Markdown is readable in Obsidian.
```
