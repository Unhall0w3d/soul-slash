# Soul/ Approved Rules

Human-approved operating rules are appended here by:

```bash
ruby bin/soul reflection approve latest
```


## 2026-07-06T17:57:16-04:00 - skill.downloads.move_to_trash

Source: `Soul/logs/tasks/20260706T211153Z-skill.downloads.move_to_trash.json`


- Moving approved cleanup candidates to Trash is the terminal cleanup action for Soul/.
- Soul/ should not empty Trash or permanently delete trashed items as part of normal cleanup.
- Trash retention and emptying are left to the operating system or the user.
- downloads.move_to_trash must consume a verified downloads.cleanup_plan log.
- downloads.move_to_trash must require --execute and --confirm MOVE_TO_TRASH before moving anything.
