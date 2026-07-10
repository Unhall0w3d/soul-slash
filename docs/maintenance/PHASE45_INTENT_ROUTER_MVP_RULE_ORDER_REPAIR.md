
# Phase 45 Rule Order and Legacy Intent Repair

The Phase 45 router ran, but the assessment still found mismatches.

## Causes

Two issues were present:

```text
downloads.inspect matched before more specific downloads cleanup/trash requests
existing workflow handling returned youtube.play instead of the new youtube_request id
```

## Repair

This repair:

```text
moves downloads_move_to_trash and downloads_cleanup_plan before downloads_inspect
normalizes legacy YouTube workflow intents in the assessor
keeps the compatibility Result class
```

## Scope

No skill execution is added.

The router still only classifies and explains.
