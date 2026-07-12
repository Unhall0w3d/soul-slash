# Phase 59 Approval Token Store

Phase 59 adds a runtime-only approval token scaffold.

## Added / changed

```text
lib/soul_core/approval_token_store.rb
lib/soul_core/approval_token_store_assessor.rb
lib/soul_core/app.rb
docs/APPROVAL_TOKEN_STORE.md
docs/USABILITY_RETARGET_BACKLOG.md
scripts/verify-approval-token-store-phase59.rb
```

## Scope

This phase adds:

```text
runtime-only token persistence
single-use enforcement
scope binding
expiry
revocation
assessment coverage
```

This phase does not add:

```text
chat approval commands
file movement
file deletion
mutation execution
background jobs
```

## Result

Soul now has the approval-token foundation needed for future explicit approve/revoke workflows.
