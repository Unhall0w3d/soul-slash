# Soul/ Restore Last Cleanup overlay

This overlay adds the rollback side of the Downloads cleanup workflow.

## Adds

- `downloads.restore_last_cleanup` skill
- dry-run-first restore behavior
- `--execute --confirm RESTORE_FROM_TRASH` execution gate
- workflow support for:

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

## Safety model

The restore skill:

- consumes the latest successful `downloads.move_to_trash` task log by default
- reads the moved item list from that log
- finds matching FreeDesktop Trash metadata under `~/.local/share/Trash/info`
- verifies the original path is still inside the cleanup target
- refuses to overwrite an existing original path
- dry-runs by default
- requires `--execute --confirm RESTORE_FROM_TRASH` before moving anything back
- removes the matching `.trashinfo` metadata only after a successful restore

It does not empty Trash. It does not permanently delete anything.

## Install

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_restore_last_cleanup_overlay.zip
chmod +x Soul/skills/downloads/restore_last_cleanup.rb
```

## Direct skill tests

Dry-run:

```bash
ruby bin/soul skill downloads.restore_last_cleanup
```

Execute:

```bash
ruby bin/soul skill downloads.restore_last_cleanup -- --execute --confirm RESTORE_FROM_TRASH
```

## Conversational workflow test

```bash
ruby bin/soul do "restore the last downloads cleanup"
ruby bin/soul respond "restore all"
ruby bin/soul respond "yeah, do it"
```

## Git workflow

Recommended branch:

```bash
git checkout -b feature/downloads-restore-last-cleanup
git add .
git commit -m "Add Downloads restore-last-cleanup workflow"
git push -u origin feature/downloads-restore-last-cleanup
```
