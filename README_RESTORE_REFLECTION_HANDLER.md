# Soul/ Restore Reflection Handler Overlay

This overlay teaches Soul/ reflection how to handle:

```text
skill.downloads.restore_last_cleanup
```

## Problem

Restore logs currently fall into the generic reflection handler, producing weak candidates like:

```text
No specific reflection handler exists for this task kind yet.
```

That candidate should not be approved.

## Fix

This overlay updates:

```text
lib/soul_core/reflection.rb
```

and adds a specific handler for:

```text
skill.downloads.restore_last_cleanup
```

The handler captures:

- restore status
- restore outcome
- source move log
- planned restore count
- restored files
- restored directories
- permanent deletions
- job completion
- restore safety rules

## Install

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_restore_reflection_handler_overlay.zip
```

## Recommended cleanup

Reject the existing generic restore reflection candidate:

```bash
ruby bin/soul reflection reject latest --reason "Generic restore reflection superseded by specific restore_last_cleanup reflection handler."
```

Then re-reflect the successful restore task log:

```bash
ruby bin/soul reflect Soul/logs/tasks/20260707T000409Z-skill.downloads.restore_last_cleanup.json
ruby bin/soul reflection show latest
```

If the new candidate looks correct:

```bash
ruby bin/soul reflection approve latest --note "Approved restore-last-cleanup as the rollback workflow for Downloads cleanup."
```

## Verify

```bash
ruby -c lib/soul_core/reflection.rb
ruby bin/soul reflect Soul/logs/tasks/20260707T000409Z-skill.downloads.restore_last_cleanup.json
ruby bin/soul reflection show latest
```
