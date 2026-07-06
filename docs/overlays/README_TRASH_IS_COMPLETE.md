# Soul/ Trash-is-complete policy overlay

This overlay updates Soul/ cleanup semantics:

Moving a file or top-level folder to Trash is considered job complete.

Soul/ does not need to empty Trash.
Soul/ does not need to permanently delete anything.
Trash lifecycle is left to the operating system or the user.

## Install

```bash
cd ~/Projects/soul
unzip ~/Downloads/soul_trash_is_complete_overlay.zip
chmod +x Soul/skills/downloads/move_to_trash.rb
```

## Test

```bash
ruby bin/soul skill downloads.move_to_trash -- --latest-plan
```

After a successful execute run, reflection should treat moved-to-Trash as cleanup completion:

```bash
ruby bin/soul reflect last
ruby bin/soul reflection show latest
```
