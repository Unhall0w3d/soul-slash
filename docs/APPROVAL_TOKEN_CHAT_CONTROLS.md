# Approval Token Chat Controls

Phase 60 adds chat controls for approval tokens.

## Commands

```text
approve downloads cleanup preview
pending approvals
revoke approval <token>
```

## Behavior

`approve downloads cleanup preview`:

```text
runs a fresh non-mutating cleanup preview
binds a single-use token to that preview
stores the token under Soul/runtime/
does not enable mutation
```

`pending approvals` lists pending runtime tokens.

`revoke approval <token>` revokes one pending token.

## Current boundary

Tokens do not execute anything in Phase 60.

`downloads.move_to_trash` remains blocked.

No file is moved, deleted, opened, or modified.
