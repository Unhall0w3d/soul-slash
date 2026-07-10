# Phase 60 Approval Token Chat Controls

Phase 60 adds chat-facing approve, list, and revoke controls.

## Added / changed

```text
lib/soul_core/approval_token_store.rb
lib/soul_core/approval_token_chat_controls.rb
lib/soul_core/approval_token_chat_controls_assessor.rb
lib/soul_core/chat_responder.rb
lib/soul_core/app.rb
docs/APPROVAL_TOKEN_CHAT_CONTROLS.md
docs/USABILITY_RETARGET_BACKLOG.md
scripts/verify-approval-token-chat-controls-phase60.rb
```

## Scope

This phase adds:

```text
approve cleanup preview
pending approval listing
approval revocation
chat rendering
assessment coverage
```

This phase does not add:

```text
file movement
file deletion
mutation execution
approval-token consumption
background jobs
```

## Result

Soul can now issue and manage runtime-only approval tokens through chat while mutation remains disabled.
