# Approval Token Store

Phase 59 adds a runtime-only approval token scaffold.

It does not enable mutation.

## Purpose

The token store provides a foundation for future approval-gated actions.

Tokens are:

```text
single-use
short-lived
scope-bound
runtime-only
revocable
```

## Default path

```text
Soul/runtime/approvals/approval_tokens.json
```

This path must remain gitignored.

## Stored fields

```text
token_id
skill_id
scope_digest
scope
issued_at
expires_at
used_at
revoked_at
status
```

## Validation rules

A token is rejected when:

```text
token_not_found
token_skill_mismatch
token_scope_mismatch
token_expired
token_revoked
token_already_used
```

## Current boundary

There is no chat approval flow yet.

There is no mutation executor yet.

`downloads.move_to_trash` remains blocked.
