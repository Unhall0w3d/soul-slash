# Downloads Cleanup Approval Design

Phase 58 defines the approval model for future Downloads cleanup mutation.

This is a design-only phase. It does not enable mutation.

## Stages

### preview

`downloads.cleanup_plan` produces a non-mutating review of candidate files.

The preview must include:

```text
candidate_count
candidate_bytes
candidate_extensions
candidate_age_buckets
candidate_size_buckets
candidate_rule
privacy
mutation
```

Filenames remain omitted by default.

### approval_token

A future approval step may generate a scoped approval token.

The approval token must be:

```text
single_use_token
token_scope_binding
short_lived
human_visible
runtime_only
```

Token scope must bind to:

```text
skill_id
candidate_rule
candidate_count
candidate_bytes
preview_timestamp
target_path
```

The token must not be committed.

### execution

A future `downloads.move_to_trash` implementation may only run when:

```text
preview_before_mutation
explicit_owner_confirmation
single_use_token
token_scope_binding
```

are all satisfied.

The execution stage must use trash_not_delete.

Permanent delete is out of scope.

### post_execution_report

Any future mutation must record:

```text
execution_history_recorded
skill_id
approved_token_id
attempted_count
moved_count
failed_count
status
timestamp
```

Filenames should remain omitted by default unless an explicit verbose/debug mode exists.

## Safety rules

```text
preview_before_mutation
explicit_owner_confirmation
single_use_token
token_scope_binding
trash_not_delete
filenames_not_printed_by_default
execution_history_recorded
dry_run_available
```

## Current enforcement

`downloads.cleanup_plan` is preview-only.

`downloads.move_to_trash remains blocked`.

Phase 58 does not add file moving.

Phase 58 does not add file deletion.

Phase 58 does not add approval tokens.

Phase 58 documents the future approval boundary so we do not bolt mutation onto the side later like a goblin with a soldering iron.
