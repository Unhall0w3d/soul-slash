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

## 2026-07-06T20:11:35-04:00 - skill.downloads.restore_last_cleanup

Source: `Soul/logs/tasks/20260707T000409Z-skill.downloads.restore_last_cleanup.json`


- downloads.restore_last_cleanup must consume a successful downloads.move_to_trash log.
- downloads.restore_last_cleanup must restore only items that Soul/ previously moved to Trash.
- downloads.restore_last_cleanup must require --execute and --confirm RESTORE_FROM_TRASH before restoring anything.
- downloads.restore_last_cleanup must refuse to overwrite an existing original path.
- downloads.restore_last_cleanup must not permanently delete files or empty Trash.
