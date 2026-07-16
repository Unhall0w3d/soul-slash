# Bulk Conversation Archive and Delete/Forget Brief

## Brief status

```text
brief_status: approved from human direction dated 2026-07-16
implementation_authorized: yes
human_review_required: yes
```

## Purpose

Make the conversation-management dialog unambiguous and allow the owner to
return Soul to a clean conversational slate. The same visible scope—exact
title, selected active conversations, or all active conversations—may be used
for either reversible archival or separately previewed permanent deletion.

## Archive behavior

- Archival remains reversible metadata-only clearing.
- Transcript, state, evidence, memory, and artifact files are not deleted.
- The UI must call it `Archive` and state that transcripts remain.
- The archive preview and action must display the exact matched conversation
  count so it cannot be confused with permanent deletion.

## Permanent delete-and-forget behavior

The permanent path may target the same scope but requires its own preview and
confirmation. Preview inventory includes:

```text
conversation count
aggregate message count
unique linked shared-memory count
artifact attachment count
owned conversation file count and bytes
retained append-only/audit categories
per-conversation title, ID, and message count
```

Execution permanently removes conversation-owned transcript, metadata, state,
and grounded-evidence files; logically forgets unique linked shared memories;
and detaches artifacts from each selected conversation without deleting artifact
files. Existing append-only safety/provenance records and exports remain.

## Bounds and confirmation

```text
maximum conversations per permanent operation: 100
maximum aggregate linked memory/artifact references: 2,000 each
preview required: yes
inventory digest required: yes
confirmation: DELETE_AND_FORGET_<COUNT>_CONVERSATIONS
retries: 0
background continuation: prohibited
```

The exact selection and all inventories are recomputed at execution. Any count,
file, memory, artifact, or digest change blocks before mutation. Invalid or
duplicate IDs block. An empty selection awaits input.

## Partial failure

The filesystem and append-only stores do not provide a cross-resource
transaction. Execution records each completed memory forget, artifact detach,
and file deletion. On error it stops immediately and returns
`blocked_for_human_review` with bounded completed-work evidence. It never retries
or continues in the background.

## Lifecycle

```text
preview → complete / awaiting_input / blocked_for_human_review
execute → complete / awaiting_input / blocked_for_human_review
```

## Prohibitions

- No background cleanup, watcher, timer, queue, service, or scheduled deletion.
- No automatic deletion after archival.
- No deletion without exact confirmation and unchanged aggregate digest.
- No artifact-file deletion.
- No erasure or rewriting of append-only safety/provenance records.
- No weakening of the existing single-conversation delete-and-forget path.

## Deterministic tests required

- 50 selected conversations preview as 50 conversations, not one active chat;
- aggregate message and resource counts are correct;
- archive and permanent-delete UI wording and routes are distinct;
- selected/title/all scopes are exact and capped;
- wrong confirmation and stale inventory block before mutation;
- shared memory IDs are logically forgotten once;
- shared artifacts are detached from each selected chat and files remain;
- permanent success removes owned conversation files and active-list entries;
- archival success retains transcripts;
- partial failure reports completed work and stops;
- no background primitive is added;
- existing single forget, Phase 12C, and Phase 13 regressions pass.

## Completion artifact

Create:

```text
docs/assessments/BULK_CONVERSATION_DELETE_FORGET.md
```

## Human authorization

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: fix archival clarity and add permanent deletion for the selected clean-slate scope
```
