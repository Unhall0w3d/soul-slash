# Downloads Cleanup Skills

Soul/ includes a bounded Downloads cleanup workflow for inspecting, planning, moving approved candidates to Trash, and restoring the most recent cleanup.

These skills are intentionally conservative. They do not permanently delete files. Apparently even software can learn not to burn down the filing cabinet.

## Related skills

```text
downloads.inspect
downloads.cleanup_plan
downloads.move_to_trash
downloads.restore_last_cleanup
```

## Natural workflow

Typical cleanup flow:

```bash
ruby bin/soul do "cleanup files in my downloads folder older than 30 days"
```

Soul/ should:

```text
inspect Downloads
build a cleanup plan
show file and top-level folder candidates
protect known project/work names
ask for selection
ask for confirmation before moving anything
move approved items to Trash only after confirmation
write task logs
close as complete when the Trash move is done
```

Candidate IDs are usually:

```text
F1, F2, F3... for files
D1, D2, D3... for top-level directories
```

Example selection responses:

```bash
ruby bin/soul respond "move all"
ruby bin/soul respond "move F1 and D2"
ruby bin/soul respond "cancel"
```

Example confirmation:

```bash
ruby bin/soul respond "yes"
```

## Direct skill usage

Direct inspection:

```bash
ruby bin/soul skill downloads.inspect -- --days 30
```

Direct cleanup plan:

```bash
ruby bin/soul skill downloads.cleanup_plan -- --days 30
```

Direct move to Trash should require an approved/verified plan and explicit execution flags. The normal conversational workflow is preferred.

## Trash policy

Downloads cleanup moves approved candidates to Trash.

It does not empty Trash.

It does not permanently delete files.

Trash retention, emptying, and manual restoration remain the responsibility of the operating system or user.

## Restore workflow

Restore the most recent successful Downloads cleanup:

```bash
ruby bin/soul do "restore the last downloads cleanup"
```

Soul/ should:

```text
find the latest successful downloads.move_to_trash task log
show restorable items
ask for selection
ask for confirmation
restore selected items to their original paths when possible
write task logs
close as complete
```

Example restore responses:

```bash
ruby bin/soul respond "restore all"
ruby bin/soul respond "restore F1"
ruby bin/soul respond "yes"
```

## Protection behavior

Downloads cleanup should preserve protected names and project-related files/folders.

Protected terms currently include project markers such as:

```text
Soul
soul
Aletheia
AletheiaUC
```

This means a test fixture named something like `soul-restore-test-file.tmp` may be intentionally skipped.

For neutral cleanup/restore tests, use neutral names such as:

```text
restore-fixture-file.tmp
restore-fixture-folder
```

## Expected terminal states

Cleanup should end as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

A completed Trash move should use final state:

```text
complete
```

not `success`.

## Logging

Task logs are written under:

```text
Soul/logs/tasks/
```

Runtime logs should not be committed.

## Reflection

After meaningful cleanup/restore runs, reflection can stage lessons:

```bash
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```

Human approval is required before any lesson/rule is promoted.
