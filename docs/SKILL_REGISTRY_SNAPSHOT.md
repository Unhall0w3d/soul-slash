# Skill Registry Snapshot

Generated: 2026-07-15T13:24:19-04:00

Source registry:

```text
Soul/skills/registry.yaml
```

This document is a generated documentation snapshot of the active skill registry. It is intended to reduce documentation drift without changing skill behavior.

## Summary

```text
skill_count: 14
registry_path: Soul/skills/registry.yaml
```

## Skills

### `chats.clear`

```text
name: chats.clear
category: uncategorized
status: unknown
```

Preview and archive active conversations by exact title or all conversations so they leave the active list without deleting transcripts.

### `chats.forget`

```text
name: chats.forget
category: uncategorized
status: unknown
```

Permanently delete one exact local conversation and logically forget shared memories derived from it.

### `cloud.providers.list`

```text
name: cloud.providers.list
category: uncategorized
status: unknown
```

List configured cloud LLM providers without making network calls.

### `cloud.providers.test`

```text
name: cloud.providers.test
category: uncategorized
status: unknown
```

Run bounded smoke tests for configured cloud LLM providers.

### `downloads.cleanup_plan`

```text
name: downloads.cleanup_plan
category: uncategorized
status: unknown
```

Read-only human-oriented cleanup plan based on downloads.inspect.

### `downloads.inspect`

```text
name: downloads.inspect
category: uncategorized
status: unknown
```

Read-only Downloads inspection and cleanup-candidate planning.

### `downloads.move_to_trash`

```text
name: downloads.move_to_trash
category: uncategorized
status: unknown
```

Approval-gated move-to-trash execution based on a verified downloads.cleanup_plan.

### `downloads.restore_last_cleanup`

```text
name: downloads.restore_last_cleanup
category: uncategorized
status: unknown
```

Approval-gated restore of the latest successful Downloads cleanup from Trash.

### `skill.brief.draft`

```text
name: skill.brief.draft
category: uncategorized
status: unknown
```

Draft a review-only Soul/ skill proposal using a configured cloud provider.

### `skill.brief.review`

```text
name: skill.brief.review
category: uncategorized
status: unknown
```

Review a Soul/ skill proposal and write a review-only artifact.

### `system.status`

```text
name: system.status
category: uncategorized
status: unknown
```

Read-only local system and Soul runtime status check.

### `weather.report`

```text
name: weather.report
category: uncategorized
status: unknown
```

Read-only weather report with temperature, humidity, air quality, and optional 3-day outlook.

### `youtube.song_search`

```text
name: youtube.song_search
category: uncategorized
status: unknown
```

Open a YouTube search for a requested song in the default Linux browser after confirmation.

### `youtube.video_resolve`

```text
name: youtube.video_resolve
category: uncategorized
status: unknown
```

Resolve a song/search query to a YouTube video candidate using the official YouTube Data API.

## Boundaries

This snapshot does not activate, disable, or modify any skill.

Refresh it with:

```bash
ruby bin/soul improve documentation-registry-refresh
```
