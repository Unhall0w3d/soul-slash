# Soul/ downloads.cleanup_plan overlay

This overlay adds a read-only planning skill:

```text
downloads.cleanup_plan
```

It wraps `downloads.inspect`, then produces a clearer cleanup plan.

It still does **not** move, delete, rename, or modify files.

## Commands

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_downloads_plan_overlay.zip
chmod +x Soul/skills/downloads/plan.rb

ruby bin/soul skills
ruby bin/soul skill downloads.cleanup_plan
ruby bin/soul skill downloads.cleanup_plan -- --older-than-days 30
ruby bin/soul skill downloads.cleanup_plan -- --path "$HOME/Downloads" --older-than-days 30
```

## Purpose

`downloads.inspect` is the raw scanner.

`downloads.cleanup_plan` is the decision/report layer.

Later, an approval-gated `downloads.move_to_trash` skill can consume this plan.
