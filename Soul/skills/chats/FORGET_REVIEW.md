# Skill Candidate Review

## Skill

Name: `chats.forget`

Risk class: Class 5 — permanent local deletion

Branch/checkpoint: `codex/phase12c-dashboard`

Date: 2026-07-15

## Candidate status

```text
candidate_complete
human_review_required
```

## Implementation summary

Adds a separate preview-first Soul skill and dashboard action for permanently deleting one conversation selected by canonical chat ID. It deletes chat metadata, messages, conversation state, and grounded-evidence files; logically deletes exact-chat-linked records through the shared memory store; and detaches registered artifacts without deleting their files.

Execution requires `DELETE_AND_FORGET_CONVERSATION` and the unchanged SHA-256 inventory digest returned by preview. Memory, artifact, inbox, request-receipt, and safety/audit ledgers are not physically purged. The UI explicitly discloses that boundary.

## Files changed

```text
Soul/skills/chats/FORGET_REVIEW.md
Soul/skills/chats/forget.rb
Soul/skills/chats/forget_skill.yaml
Soul/skills/registry.yaml
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
assets/dashboard/index.html
docs/soul/PHASE12C_CONVERSATION_DELETE_FORGET_AMENDMENT.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/conversation_forget_service.rb
lib/soul_core/conversation_forget_service_assessor.rb
lib/soul_core/intent_router.rb
scripts/verify-conversation-delete-and-forget-skill.rb
```

## Commands run

```text
ruby scripts/verify-conversation-delete-and-forget-skill.rb
ruby scripts/verify-conversation-list-clearing-skill.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
node --check assets/dashboard/dashboard.js
find lib scripts bin Soul/skills -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
git diff --check
```

## Deterministic test results

```text
PASS: 15/15 delete-and-forget assessment checks.
PASS: exact-ID, preview digest, confirmation, drift, symlink, memory, artifact, facade, routing, and dashboard checks.
PASS: conversation-list clearing regression.
PASS: Phase 12C foreground dashboard regression.
PASS: Phase 12B and earlier regressions.
PASS: all Ruby syntax, JavaScript syntax, and repository whitespace checks.
PASS: live dashboard preview against an existing conversation; execute remained disabled, no browser errors occurred, and no live data was deleted.
PENDING: human acceptance.
```

## Local LLM eval results

```text
Not required. Intent routing, authorization gates, inventory binding, and deletion behavior are deterministic.
No model output authorizes preview or execution.
```

## Memory keys added or used

```text
Added: none
Used: shared conversation memory records linked by exact chat_id or exact source reference
Mutation: append the existing logical-deletion event; never physically purge the shared ledger
```

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Safety and persistence check

```text
Permanent local deletion added: yes, explicitly authorized for one exact conversation
Delete-all added: no
Title-based deletion added: no
Physical shared-memory purge added: no
Artifact file deletion added: no
Append-only safety/audit deletion added: no
Preview and digest required: yes
Exact confirmation required: yes
Symlink protection: yes
Persistent/background behavior added: no
Skill-private memory added: no
```

## Known weaknesses

- Permanent file deletion has no rollback; that is the explicit purpose of this Class 5 skill.
- Filesystem failure after earlier logical-memory deletions or artifact detaches can produce a disclosed partial mutation requiring human review.
- Append-only memory events still contain prior memory content, although deleted records are excluded from active retrieval. Physical ledger purge remains outside the approved memory policy.
- Artifact provenance, inbox deliveries, request receipts, exports, backups, filesystem snapshots, and external copies may retain identifiers or historical data.
- Existing exported memory snapshots are not rewritten or deleted.
- The action is available only for the currently selected dashboard conversation; there is no delete-all action.

## Human review checklist

```text
[ ] Permanent deletion scope matches the explicit owner request
[ ] Exact canonical chat ID—not title—binds the target
[ ] Preview inventories every in-scope category
[ ] Inventory digest prevents stale execution
[ ] Exact confirmation is appropriately explicit
[ ] Chat metadata, transcript, state, and evidence deletion are acceptable
[ ] Shared-memory logical deletion is acceptable
[ ] Retained memory ledger and export limitation is understood
[ ] Artifact detachment without artifact deletion is acceptable
[ ] Audit/provenance retention is acceptable
[ ] Partial-failure behavior is predictable
[ ] No delete-all or background behavior was added
[ ] Deterministic tests are meaningful
[ ] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: pending
Reviewer: human owner
Date:
Decision summary:
Required changes:
```
