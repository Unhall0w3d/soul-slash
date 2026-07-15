# Phase 12C Approved Amendment: Conversation List Clearing

```text
amendment_status: approved
implementation_authorized: yes
human_visual_review_required: yes
human_merge_review_required: yes
```

The human owner explicitly requested a Soul skill that clears conversations from the dashboard list by title or clears all conversations on 2026-07-14. This amendment narrowly expands Phase 12C to provide that behavior without authorizing transcript deletion.

## Meaning of clear

`clear` means set existing conversation metadata to `archived: true` so active Chat lists no longer display it. Message JSONL files and chat metadata remain present. No file is deleted, moved, truncated, overwritten with unrelated content, exported, or uploaded.

This is a Class 3 local user-data metadata modification. The existing `archived` field is the canonical storage mechanism. A future restore/archive-management view may expose reversal; Phase 12C must report that archived data remains locally stored.

## Approved operations

- Preview active conversations matching one exact title, case-insensitively after trimming.
- Preview all active conversations.
- Disclose every matched chat ID and title, including duplicate-title matches.
- Cap a single preview/execution at 500 conversations and block larger operations for human review.
- Require the exact literal confirmation `CLEAR_CONVERSATIONS`.
- Require the execution to carry the preview's match-set digest; block if the active match set changes.
- Archive the verified matches sequentially in the foreground.
- Hide archived chats from normal CLI, application, and dashboard lists.
- Register `chats.clear` as a Soul skill and expose the same service through versioned application operations for the dashboard.
- Add a bounded modal dashboard flow for exact-title or all-conversation preview and execution.

## Explicitly out of scope

- Permanent deletion, Trash movement, truncation, secure erase, or physical purge.
- Clearing message contents while retaining a chat shell.
- Matching title substrings, regular expressions, message contents, summaries, or model guesses.
- Silently choosing one chat when titles are duplicated.
- Execution without preview digest and exact confirmation.
- Automatic cleanup, retention schedules, background archival, watchers, polling, or recurring tasks.
- Cloud calls, model calls, memory deletion, artifact deletion, approval mutation, or activity-history deletion.
- Restoring archived chats in this slice.

## Lifecycle

Every invocation terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

Preview is read-only. Execution is synchronous, bounded to 500 metadata updates, and returns per-chat results. A stale digest, excessive match set, corrupt metadata, or partial failure blocks for human review and never deletes transcript files.

## Required deterministic tests

- Default active lists exclude archived chats while explicit internal inspection may include them.
- Exact-title matching is trimmed and case-insensitive but never substring-based.
- Duplicate titles are all disclosed in preview.
- Missing selector, conflicting selectors, empty title, no matches, and more than 500 matches fail predictably.
- Preview performs no writes.
- Execution requires exact confirmation and a matching digest.
- A changed match set blocks before mutation.
- Verified execution archives exactly the previewed records and preserves all metadata/message files.
- Repeated execution is safe and reports no active matches.
- Skill runner retains its independent write-skill confirmation gate.
- Dashboard renders a preview before enabling execution and states that transcripts remain stored.
- Dashboard refreshes the active list after completion and uses safe DOM text APIs.
- No permanent-delete or background primitive is introduced.
- Phase 12C, Phase 12B, and earlier regressions pass.

## Human approval

```text
Outcome: approved by explicit feature request
Reviewer: human owner
Date: 2026-07-14
Approved behavior: clear conversations from the active list by title or all conversations
Safety interpretation: reversible metadata archival, not permanent deletion
Implementation authorized: yes
```
