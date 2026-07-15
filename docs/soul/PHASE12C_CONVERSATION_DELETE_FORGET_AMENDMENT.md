# Phase 12C Conversation Delete-and-Forget Amendment

Status: human-authorized implementation candidate

Authorization: on 2026-07-15 the human owner requested the ability to delete and forget one specified conversation, including its history, contents, and memories.

## Approved boundary

Add a separate `chats.forget` Class 5 skill and dashboard action for one canonical chat ID. Do not broaden `chats.clear`, and do not provide delete-all behavior.

Preview must inventory the exact target and return a SHA-256 digest. Execution requires that unchanged digest and the literal `DELETE_AND_FORGET_CONVERSATION`.

Execution may:

- permanently delete the selected chat metadata and message transcript;
- permanently delete its bounded conversation-state and grounded-evidence files when present;
- logically delete shared-memory records whose `chat_id` or source reference is the exact chat ID;
- detach registered artifacts from the chat without deleting artifact files.

Execution must retain and disclose:

- the append-only memory ledger and its logical-deletion events;
- artifact provenance and attachment audit events;
- inbox, application receipt, and other content-free safety/audit records;
- artifact files and exported memory snapshots.

Those retained records must not be used to reconstruct the forgotten chat through normal conversation retrieval.

## Safety contract

- One exact canonical chat ID only; titles never authorize deletion.
- Preview is read-only and bounded to 500 linked memories and 500 attached artifacts.
- Any target or inventory drift blocks before mutation.
- Symlinked or non-regular conversation-owned files block execution.
- Logical memory deletion precedes permanent file deletion so a memory-ledger failure leaves the transcript available for review.
- A partial failure terminates as `blocked_for_human_review` and reports completed categories.
- No model output can preview, confirm, or execute the operation.
- No service, watcher, schedule, listener, background loop, or skill-private memory is added.

## Lifecycle

Every invocation terminates as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`.

## Human review focus

Confirm the irreversible scope, retained audit/provenance boundary, exact-ID selection, digest binding, confirmation phrase, partial-failure disclosure, and deterministic tests before merge.
