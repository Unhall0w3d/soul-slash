# Soul/ downloads.inspect overlay

This overlay adds the first practical read-only Soul/ skill:

```text
downloads.inspect
```

It scans a target directory, defaults to `~/Downloads`, and produces a JSON report with:

- total entries
- old files
- protected project-related files
- cleanup candidates
- uncertain entries
- warnings
- verification fields

It does **not** move, delete, rename, or modify files.

## Commands

After extracting into `~/Projects/soul`:

```bash
chmod +x Soul/skills/downloads/inspect.rb
ruby bin/soul skills
ruby bin/soul skill downloads.inspect
ruby bin/soul skill downloads.inspect -- --older-than-days 30
ruby bin/soul skill downloads.inspect -- --path "$HOME/Downloads" --older-than-days 30
```

The `--` separates Soul/ CLI arguments from skill-specific arguments.
