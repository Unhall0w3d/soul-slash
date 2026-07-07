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

## 2026-07-07T01:14:30-04:00 - skill.weather.report

Source: `Soul/logs/tasks/20260707T051214Z-skill.weather.report.json`


- weather.report must remain read-only and must not write local files from the skill itself.
- weather.report should distinguish brief completion from detailed workflow completion.
- Weather workflows should use deterministic API data for temperature, humidity, and air quality rather than model guessing.

## 2026-07-07T12:22:50-04:00 - skill.weather.report

Source: `Soul/logs/tasks/20260707T162022Z-skill.weather.report.json`


- A weather override location should be collected from the user and then resolved through the same deterministic geocoding path as direct weather requests.
- International weather locations should retain geocoding evidence, including parsed country code, geocoding attempts, and resolved location.
- Weather geocoding should normalize common country aliases while still keeping an unfiltered city-only fallback.
- weather.report must remain read-only and must not write local files from the skill itself.
- Weather workflows should use deterministic API data for temperature, humidity, air quality, and forecast signals rather than model guessing.

## 2026-07-07T12:23:02-04:00 - skill.weather.report

Source: `Soul/logs/tasks/20260707T161943Z-skill.weather.report.json`


- International weather locations should retain geocoding evidence, including parsed country code, geocoding attempts, and resolved location.
- Weather event classification must not label Open-Meteo rain-shower codes 80..82 as snow; snow should remain limited to snow codes 71..77 and 85..86.
- weather.report must remain read-only and must not write local files from the skill itself.
- Weather workflows should use deterministic API data for temperature, humidity, air quality, and forecast signals rather than model guessing.
