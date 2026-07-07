# Soul/ Move-to-Trash Workflow State Fix

This overlay fixes the conversational cleanup execution path.

## Problem

`lib/soul_core/workflow_session.rb` runs:

```bash
downloads.move_to_trash --workflow-state <session> --execute --confirm MOVE_TO_TRASH
```

but the current `Soul/skills/downloads/move_to_trash.rb` does not accept `--workflow-state`.

That causes the selection/confirmation flow to reach the final step, but the move skill refuses the unknown option and nothing is moved.

## Fix

This overlay updates:

```text
Soul/skills/downloads/move_to_trash.rb
```

to support:

```bash
--workflow-state PATH
```

When a workflow state is provided, the skill uses:

```json
selected_candidates
```

from that workflow session instead of moving every candidate from the latest plan.

## Safety behavior

The skill still:

- requires `--execute`
- requires `--confirm MOVE_TO_TRASH`
- consumes the original verified cleanup plan
- refuses paths outside the cleanup target
- refuses protected paths
- refuses missing paths
- refuses type mismatches
- moves to Trash only
- does not permanently delete anything

## Test fixture note

Do not use test names containing protected terms such as:

```text
soul
Soul
Aletheia
AletheiaUC
```

Downloads cleanup intentionally excludes those names.

Use neutral fixture names such as:

```text
restore-fixture-file.tmp
restore-fixture-folder
```

## Verify

```bash
ruby -c Soul/skills/downloads/move_to_trash.rb
find lib Soul/skills -name "*.rb" -print0 | xargs -0 -n1 ruby -c
```

## Test

```bash
rm -rf ~/Downloads/restore-fixture-file.tmp ~/Downloads/restore-fixture-folder

mkdir -p ~/Downloads/restore-fixture-folder
touch ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-file.tmp
touch -d "10 days ago" ~/Downloads/restore-fixture-folder

ruby bin/soul do "cleanup files in my downloads folder older than 3 days"
ruby bin/soul respond "move all"
ruby bin/soul respond "yeah, do it"

ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"

ls -la ~/Downloads | grep restore-fixture
```
