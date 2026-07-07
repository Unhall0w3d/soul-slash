# Soul/ Approved Lessons

Human-approved lessons are appended here by:

```bash
ruby bin/soul reflection approve latest
```


## 2026-07-06T20:11:35-04:00 - skill.downloads.restore_last_cleanup

Source: `Soul/logs/tasks/20260707T000409Z-skill.downloads.restore_last_cleanup.json`


- A Downloads restore job is complete when all approved restore candidates are returned from Trash to their original paths.
- The restore-last-cleanup workflow provides the rollback path for approved Downloads cleanup actions.

## 2026-07-07T01:14:30-04:00 - skill.weather.report

Source: `Soul/logs/tasks/20260707T051214Z-skill.weather.report.json`


- weather.report is a read-only network skill that can complete without any write approval.
- The brief weather workflow should ask whether the user wants a detailed 3-day outlook before closing as complete.
- Detailed weather reports should close with final_state complete rather than success language.
