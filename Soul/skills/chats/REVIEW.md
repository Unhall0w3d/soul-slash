# Skill Candidate Review

## Skill

Name: `chats.clear`

Risk class: Class 3 — local user-data modification

Branch/checkpoint: `codex/phase12e-review-center`

Date: 2026-07-15

## Candidate status

```text
candidate_complete
human_review_required
```

## Implementation summary

Adds a preview-first Soul skill and dashboard control that archives active conversations by exact title, a human-selected set of exact chat IDs, or all conversations. Clearing removes records from active lists by setting the existing `archived` metadata flag. It does not delete metadata files or message transcripts.

Execution requires the exact literal `CLEAR_CONVERSATIONS` and the SHA-256 match digest returned by preview. A changed match set or selected chat becoming inactive blocks before mutation. Duplicate titles are shown as multiple matches, selected IDs must be unique and exact, and operations above 500 matches block for human review.

## Files changed

```text
Soul/skills/chats/REVIEW.md
Soul/skills/chats/clear.rb
Soul/skills/chats/clear_skill.yaml
Soul/skills/registry.yaml
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
assets/dashboard/index.html
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE12C_FOREGROUND_DASHBOARD.md
docs/soul/FOREGROUND_LOOPBACK_DASHBOARD.md
docs/soul/PHASE12C_CONVERSATION_CLEARING_AMENDMENT.md
lib/soul_core/app.rb
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/chat_store.rb
lib/soul_core/conversation_clear_service.rb
lib/soul_core/conversation_clear_service_assessor.rb
lib/soul_core/intent_router.rb
lib/soul_core/phase12c_foreground_dashboard_assessor.rb
scripts/verify-conversation-list-clearing-skill.rb
```

## Commands run

```text
ruby bin/soul assess conversation-list-clearing --json
ruby bin/soul assess conversation-list-clearing
ruby scripts/verify-conversation-list-clearing-skill.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
node --check assets/dashboard/dashboard.js
find lib scripts bin Soul/skills -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
git diff --check
```

## Deterministic test results

```text
PASS: 17/17 conversation-clearing assessment checks, including exact selected-set preview, stale-set blocking, and selected-only execution.
PASS: skill registry, service boundary, digest, and dashboard source checks.
PASS: Phase 12C, Phase 12B, and earlier regressions.
PASS: repository whitespace checks.
PASS: local browser exact-title and all-conversation preview flows; execution remained disabled and no live data was archived.
PASS: dashboard browser console contained no application errors.
PENDING: human acceptance.
```

## Local LLM eval results

```text
Not required by the approved amendment.
Intent routing and safety behavior are deterministic.
No model output authorizes preview or execution.
```

## Memory keys

Reads:

```text
- none
```

Writes/updates:

```text
- none
```

Forget behavior:

```text
Unchanged. Conversation clearing is archival metadata, not memory deletion.
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
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Permanent deletion added: no
Transcript truncation added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Known weaknesses

- Archived conversations do not yet have a dashboard restore/archive-management view; their metadata can support one in a later reviewed slice.
- Exact-title mode intentionally matches every active chat with the same title instead of guessing among duplicates.
- The dashboard selection is bounded to the active conversations currently loaded in the list; the CLI accepts up to 500 exact IDs.
- The 500-record cap requires the user to narrow unusually large active sets before archival.
- Metadata writes are sequential; an unexpected failure after earlier records archive returns `blocked_for_human_review` with completed records disclosed.
- The dashboard does not currently retain an audit view of archived conversations.

## Human review checklist

```text
[ ] Clear means archive/hide, not delete
[ ] Exact-title and all modes match the requested behavior
[ ] Selected mode archives exactly the checked conversations and leaves unselected conversations active
[ ] Empty, duplicate, malformed, or stale selected IDs fail safely
[ ] Duplicate titles are disclosed clearly
[ ] Preview is required before execution
[ ] Confirmation phrase is appropriately explicit
[ ] Match digest prevents stale-plan execution
[ ] Transcript and metadata files remain present
[ ] Active list excludes archived records
[ ] Dashboard dialog is visually and operationally clear
[ ] Failure and partial-mutation behavior is predictable
[ ] No background or permanent-delete behavior exists
[ ] Deterministic tests are meaningful
[ ] Known weaknesses are acceptable
[ ] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: approved
Reviewer: human owner
Date: 2026-07-15
Decision summary: Exact multi-conversation archival, preview, confirmation, and transcript-retention behavior accepted in the live dashboard.
Required changes: none
```
