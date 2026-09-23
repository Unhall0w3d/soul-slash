# Downloads Move to Trash

Phase 62 enables the first approval-gated filesystem mutation.

## Required chat flow

```text
approve downloads cleanup preview
dry run downloads move <token>
move approved downloads to trash <token> confirm
```

## Safety controls

Execution requires:

```text
a pending approval token
matching cleanup scope
matching candidate count and bytes
matching manifest digest when available
literal confirm keyword
```

The executor moves candidates to the desktop trash, never permanent delete.

It writes freedesktop-style `.trashinfo` metadata and uses collision-safe destination names.

## Reporting

The post-execution report includes:

```text
attempted_count
moved_count
failed_count
moved_bytes
failed_bytes
token_status
permanent_delete: false
filenames_omitted: true
```

The token is consumed after an execution attempt.

Execution is recorded in local chat execution history.
# Focused regression checks during active development

Run `ruby scripts/verify-downloads-move-to-trash-phase62.rb --functional-only`
to check the fixture-based trash behavior and confirmation boundaries without
claiming repository curation approval. The default invocation still includes
the strict curation check. Untracked review artifacts must be reviewed separately;
do not delete or broadly stage them to make functional checks pass.
