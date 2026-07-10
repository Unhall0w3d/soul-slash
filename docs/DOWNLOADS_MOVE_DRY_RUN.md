# Downloads Move Dry-Run

Phase 61 adds an approval-gated dry-run for future Downloads movement.

## Chat flow

```text
approve downloads cleanup preview
dry run downloads move <token>
pending approvals
```

## Dry-run output

```text
would_move_count
would_move_bytes
candidate extensions
candidate age buckets
candidate size buckets
mutation: none
token_consumed: false
```

## Safety posture

The token must be:

```text
present
pending
unexpired
unrevoked
scope-bound to the current cleanup preview
```

Dry-run does not consume the token.

Dry-run does not move or delete files.

Real `downloads.move_to_trash` execution remains blocked.
