
# Intent Router MVP

Phase 45 adds a deterministic intent router for Soul chat.

## Purpose

The chat layer should stop returning the same fallback for every unknown request.

This phase maps simple owner utterances into known intent categories without executing skills.

## Commands

```bash
ruby bin/soul assess intent-router
ruby bin/soul assess intent-router --json
```

Aliases:

```bash
ruby bin/soul assess intent-router-mvp
ruby bin/soul assess chat-intents
```

## Initial intents

```text
identity
skill_catalog
repo_status
pending_work
weather_request
downloads_inspect
downloads_cleanup_plan
downloads_move_to_trash
cloud_providers
youtube_request
skill_brief
unknown
```

## Safety posture

The router can identify candidate skills.

It cannot execute them.

It can say:

```text
this sounds like downloads.inspect
this sounds like weather.report
this would require confirmation
this is unknown
```

It must not run the skill from chat yet.

## Result

Soul can point at the correct tool shelf.

It still cannot swing the tools until the skill invocation planner exists.
