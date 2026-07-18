# Music project archive deletion brief

## Approved intent

Allow the Operator to permanently delete one selected composition from the
Music Studio Composition Archive.

Deletion requires a fresh preview, a digest of the exact current project tree,
and the exact phrase `DELETE_MUSIC_PROJECT`. It removes the project record,
generated candidates, FLAC/MP3 archive copies, inputs, logs, transcription
evidence, reviews and review history, rejection receipts, and project-local
export receipts.

Finished songs previously exported under `~/Music/soul-music` are explicitly
outside this operation and remain untouched. Their destinations are shown in
the preview when a valid project-local export receipt identifies them.

The operation stops if the project owns an active music-generation lease, a
path is a symlink or unsupported filesystem object, the inventory exceeds its
bounded limits, or project state changes after preview. It processes one
project, at most 5,000 files and 10 GiB per invocation.

Lifecycle outcomes are `blocked_for_human_review` for preview, stale state, or
integrity blockers; `awaiting_input` for invalid/missing input; and `complete`
only after confirmed deletion is verified absent. There is no queue, retry,
service, watcher, scheduler, or background continuation.
