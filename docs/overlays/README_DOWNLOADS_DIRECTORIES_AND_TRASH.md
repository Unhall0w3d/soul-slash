# Soul/ Downloads directories + trash overlay

This overlay changes Downloads cleanup behavior:

- Top-level directories in `~/Downloads` are now considered by `downloads.inspect`.
- The skill still does not recurse deeply into subfolders.
- A top-level directory can become a cleanup candidate if it is older than the threshold and not protected.
- `downloads.cleanup_plan` can now present both files and directories as candidates.
- New approval-gated skill: `downloads.move_to_trash`.

## Safety model

`downloads.move_to_trash`:

- consumes an existing `downloads.cleanup_plan` task log
- defaults to dry-run
- requires `--execute`
- requires exact confirmation: `--confirm MOVE_TO_TRASH`
- moves to Trash using `gio trash` or `trash-put`
- refuses to permanently delete files
- refuses paths outside the planned target directory
- refuses protected items
- refuses paths not present in the verified cleanup plan

## Install

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_downloads_directories_and_trash_overlay.zip
chmod +x Soul/skills/downloads/inspect.rb
chmod +x Soul/skills/downloads/plan.rb
chmod +x Soul/skills/downloads/move_to_trash.rb
```

## Test read-only planning

```bash
ruby bin/soul skill downloads.inspect -- --older-than-days 1
ruby bin/soul skill downloads.cleanup_plan -- --older-than-days 1
```

## Dry-run Trash move from latest plan

```bash
ruby bin/soul skill downloads.move_to_trash -- --latest-plan
```

## Execute Trash move from latest plan

```bash
ruby bin/soul skill downloads.move_to_trash -- --latest-plan --execute --confirm MOVE_TO_TRASH
```

The execution command should only be run after reviewing the cleanup plan.
