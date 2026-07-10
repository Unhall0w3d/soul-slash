# Phase 62 Downloads Move to Trash

Phase 62 enables the first approval-gated local filesystem mutation.

## Added / changed

```text
lib/soul_core/downloads_move_to_trash_executor.rb
lib/soul_core/downloads_move_to_trash_assessor.rb
lib/soul_core/chat_responder.rb
lib/soul_core/app.rb
docs/DOWNLOADS_MOVE_TO_TRASH.md
docs/USABILITY_RETARGET_BACKLOG.md
scripts/verify-downloads-move-to-trash-phase62.rb
```

## Safety boundary

```text
trash only
never permanent delete
explicit token
scope validation
literal confirm
single-use token
execution history
filenames omitted from normal reports
```

## Result

Soul can move approved Downloads candidates to desktop trash and report the outcome.
