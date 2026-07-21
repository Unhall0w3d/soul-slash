# Assistant Skill Catalog

Generated: 2026-07-20T21:49:28-04:00

Source registry:

```text
Soul/skills/registry.yaml
```

This catalog explains registered Soul skills in language suitable for chat, intent routing, and safe skill invocation planning.

It does not activate, disable, or modify any skill.

## Skill count

```text
20
```

## Skills

### Chats Clear

```text
id: chats.clear
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
```

Preview and archive active conversations by exact title or all conversations so they leave the active list without deleting transcripts.

Example ways the owner might ask for this:

- use chats clear
- run chats.clear
- prepare this first and ask before changing anything

### Chats Forget

```text
id: chats.forget
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
```

Permanently delete one exact local conversation and logically forget shared memories derived from it.

Example ways the owner might ask for this:

- use chats forget
- run chats.forget
- prepare this first and ask before changing anything

### Cloud Providers List

```text
id: cloud.providers.list
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
```

List configured cloud LLM providers without making network calls.

Example ways the owner might ask for this:

- list cloud providers
- what cloud providers are configured

### Cloud Providers Test

```text
id: cloud.providers.test
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
```

Run bounded smoke tests for configured cloud LLM providers.

Example ways the owner might ask for this:

- test cloud providers
- check provider connectivity

### Cores Activate

```text
id: cores.activate
category: runtime_control
status: available
risk: approval_required
confirmation_required: true
```

Preview and activate one configured Core without rebooting while preserving active-work, lease, digest, and exact click-approval checks.

Example ways the owner might ask for this:

- switch to Music Core
- activate AMD-Free Core
- prepare this first and ask before changing anything

### Creative Companion Production

```text
id: creative.companion_production
category: creative_studios
status: partial
risk: approval_required
confirmation_required: true
```

Coordinate reviewed music and visual candidates, including new or existing sources, then advance explicit binding, static companion rendering, export, and local upload-package gates.

Example ways the owner might ask for this:

- make a song and image, then prepare the video
- use this kept image with that kept song
- prepare this first and ask before changing anything

### Creative Music Production

```text
id: creative.music_production
category: creative_studios
status: available
risk: approval_required
confirmation_required: true
```

Gather a music brief through chat, preserve user-required decisions, generate and review candidates, translate recorded revision feedback, and prepare exact kept-song export or rejected-candidate deletion gates.

Example ways the owner might ask for this:

- make a song
- help me compose a local music candidate
- prepare this first and ask before changing anything

### Creative Visual Production

```text
id: creative.visual_production
category: creative_studios
status: available
risk: approval_required
confirmation_required: true
```

Gather or draft a visual brief through chat, generate and review a local still, and translate a recorded revise review into one exact source-preserving guided edit with an authenticated image result.

Example ways the owner might ask for this:

- make an image
- create cover artwork with me
- prepare this first and ask before changing anything

### Downloads Cleanup Plan

```text
id: downloads.cleanup_plan
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
```

Read-only human-oriented cleanup plan based on downloads.inspect.

Example ways the owner might ask for this:

- plan a downloads cleanup
- what can be cleaned up safely

### Downloads Inspect

```text
id: downloads.inspect
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
```

Read-only Downloads inspection and cleanup-candidate planning.

Example ways the owner might ask for this:

- inspect my downloads
- show me what is in downloads

### Downloads Move To Trash

```text
id: downloads.move_to_trash
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
```

Approval-gated move-to-trash execution based on a verified downloads.cleanup_plan.

Example ways the owner might ask for this:

- move approved downloads to trash
- execute the cleanup plan
- prepare this first and ask before changing anything

### Downloads Restore Last Cleanup

```text
id: downloads.restore_last_cleanup
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
```

Approval-gated restore of the latest successful Downloads cleanup from Trash.

Example ways the owner might ask for this:

- restore the last downloads cleanup
- undo the last cleanup
- prepare this first and ask before changing anything

### Skill Brief Draft

```text
id: skill.brief.draft
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
```

Draft a review-only Soul/ skill proposal using a configured cloud provider.

Example ways the owner might ask for this:

- draft a skill brief
- help me design a new skill

### Skill Brief Review

```text
id: skill.brief.review
category: uncategorized
status: unknown
risk: approval_required
confirmation_required: true
```

Review a Soul/ skill proposal and write a review-only artifact.

Example ways the owner might ask for this:

- review this skill brief
- check whether this skill proposal is safe
- prepare this first and ask before changing anything

### System Status

```text
id: system.status
category: uncategorized
status: unknown
risk: read_only
confirmation_required: false
```

Read-only local system and Soul runtime status check.

Example ways the owner might ask for this:

- check system status
- how is the system doing

### Weather Report

```text
id: weather.report
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
```

Read-only weather report with temperature, humidity, air quality, and optional 3-day outlook.

Example ways the owner might ask for this:

- get the weather
- what is the weather report

### Web Lookup

```text
id: web.lookup
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
```

Bounded DuckDuckGo Instant Answer lookup for narrow orientation; not a general research backend.

Example ways the owner might ask for this:

- use web lookup
- run web.lookup

### Web Research

```text
id: web.research
category: uncategorized
status: unknown
risk: network_or_provider_check
confirmation_required: false
```

Bounded foreground public-web search and HTTPS source retrieval with provenance and SSRF protection.

Example ways the owner might ask for this:

- use web research
- run web.research

### Youtube Song Search

```text
id: youtube.song_search
category: uncategorized
status: unknown
risk: low
confirmation_required: false
```

Open a YouTube search for a requested song in the default Linux browser after confirmation.

Example ways the owner might ask for this:

- search YouTube for a song
- find this song on YouTube

### Youtube Video Resolve

```text
id: youtube.video_resolve
category: uncategorized
status: unknown
risk: low
confirmation_required: false
```

Resolve a song/search query to a YouTube video candidate using the official YouTube Data API.

Example ways the owner might ask for this:

- resolve a YouTube video
- find the best YouTube video candidate

## Risk language

```text
read_only: can inspect or report without changing local state
review_only: drafts or reviews artifacts without promotion
network_or_provider_check: may involve configured provider/API testing
approval_required: must ask before changing local state
unknown: needs routing caution until classified
```

## Future use

This catalog should feed chat explanations, intent routing, and skill invocation planning.
