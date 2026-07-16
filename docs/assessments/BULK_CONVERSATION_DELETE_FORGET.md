# Bulk Conversation Archive and Delete/Forget Review

## Skill

Name: Scoped conversation archive and permanent delete/forget

Risk class: Class 5 — permanent local deletion

Branch/checkpoint: `main` candidate, not yet committed

Date: 2026-07-16

## Candidate status

```text
candidate_complete
human_review_required
```

## Implementation summary

The dashboard now uses one explicit exact-title, selected-conversations, or
all-active-conversations scope for two visibly separate actions. Archive keeps
the existing metadata-only behavior and says that transcripts remain.
Permanent deletion has an independent aggregate inventory preview, unchanged
inventory digest, and count-specific confirmation phrase. It removes
conversation-owned files, logically forgets unique linked shared memories, and
detaches artifacts per conversation while retaining artifact files and
append-only records.

## Files changed

```text
- assets/dashboard/dashboard.js
- assets/dashboard/index.html
- docs/soul/BULK_CONVERSATION_DELETE_FORGET_BRIEF.md
- docs/assessments/BULK_CONVERSATION_DELETE_FORGET.md
- lib/soul_core/application_contract.rb
- lib/soul_core/application_facade.rb
- lib/soul_core/bulk_conversation_forget_assessor.rb
- lib/soul_core/conversation_clear_service_assessor.rb
- lib/soul_core/conversation_forget_service.rb
- lib/soul_core/conversation_forget_service_assessor.rb
- scripts/verify-bulk-conversation-delete-forget.rb
```

## Commands run

```text
ruby -c lib/soul_core/conversation_forget_service.rb
ruby -c lib/soul_core/bulk_conversation_forget_assessor.rb
ruby -c scripts/verify-bulk-conversation-delete-forget.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-bulk-conversation-delete-forget.rb
ruby scripts/verify-conversation-delete-and-forget-skill.rb
ruby scripts/verify-conversation-list-clearing-skill.rb
```

## Deterministic test results

```text
Bulk verifier: candidate_ready; 14/14 checks passed.
Existing single delete-and-forget verifier: candidate_ready; 15/15 checks passed.
50 selected conversations: previewed as 50 with 100 aggregate fixture messages.
Wrong confirmation: awaiting_input with no file mutation.
Stale digest: blocked_for_human_review with no file mutation.
Shared memory: forgotten once.
Shared artifact: detached from both chats; artifact file retained.
Injected partial failure: stopped immediately and reported the one completed memory deletion.
Archive regression and its Phase 12C-and-earlier chain: passed.
Phase 13A integrated acceptance: passed.
Phase 13C milestone closeout: passed.
```

## Local LLM eval results

```text
Not run. This change is deterministic destructive-action routing and storage
behavior; an LLM eval is not an authorized safety validator.
```

## Memory keys

Reads:

```text
- shared conversation-memory records linked by chat_id or source.reference
```

Writes/updates:

```text
- existing shared memory layer receives logical-deletion events only
- no skill-private memory store added
```

Forget behavior:

```text
- unique linked memory IDs are logically deleted once
- append-only memory events and tombstones remain and are disclosed
```

## Lifecycle states touched

```text
complete
awaiting_input
blocked_for_human_review
```

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Known weaknesses

```text
- Filesystem, memory ledger, and artifact ledger do not share a transaction.
  Partial failures stop and report completed work but require human repair.
- Permanent deletion is limited to 100 active conversations per operation and
  2,000 aggregate memory or artifact references; larger scopes must be split.
- Append-only safety/provenance records and prior exports are retained.
- Artifact files remain even when all selected conversation attachments are removed.
- Archived conversations are outside the active dashboard scope; this change
  permanently deletes active conversations selected before archival.
```

## Human review checklist

```text
[ ] Select all shown and confirm the permanent preview count matches the selection count.
[ ] Confirm aggregate message count is plausible and each title/ID is listed.
[ ] Confirm Archive says transcripts remain and does not imply deletion.
[ ] Confirm permanent deletion says it cannot be undone.
[ ] Confirm the required phrase contains the exact previewed conversation count.
[ ] Confirm changing scope invalidates both previews.
[ ] Confirm retained append-only/audit and artifact-file disclosures are acceptable.
[ ] Approve or reject the Class 5 candidate for commit.
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Approved the unified scoped archive and permanent delete/forget dashboard flow after live review.
Required changes: none
```
