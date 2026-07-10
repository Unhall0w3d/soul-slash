# Phase 61 Downloads Move Dry-Run

Phase 61 adds an approval-token-gated dry-run executor.

## Added / changed

```text
lib/soul_core/downloads_move_dry_run_executor.rb
lib/soul_core/downloads_move_dry_run_assessor.rb
lib/soul_core/chat_responder.rb
lib/soul_core/app.rb
docs/DOWNLOADS_MOVE_DRY_RUN.md
docs/USABILITY_RETARGET_BACKLOG.md
scripts/verify-downloads-move-dry-run-phase61.rb
```

## Result

Soul can validate an approval token and report what would move without mutating the filesystem or consuming the token.
