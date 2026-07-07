# youtube.video_resolve

Planned skill.

## Purpose

Resolve a song/search query to a YouTube video candidate using an official API-backed resolver.

## Proposed provider

```text
YouTube Data API v3
```

Required config for live mode:

```text
YOUTUBE_DATA_API_KEY
```

## Current status

```text
planned
```

This document does not implement the resolver.

See:

```text
docs/implementation/YOUTUBE_VIDEO_RESOLVER_PLAN.md
```

## Intended behavior

```text
user provides song/search query
Soul/ calls official YouTube Data API
Soul/ returns candidate title/channel/video ID/watch URL
Soul/ does not open browser
Soul/ asks for confirmation in a later workflow before opening
```

Opening the browser remains the job of:

```text
youtube.song_search --url <watch_url>
```

## Boundary

The resolver must not:

```text
scrape YouTube
download media
extract streams
bypass ads or access controls
open a browser
select and launch without confirmation
print or log API key values
run persistently
store durable song history
```

## Planned direct usage

```bash
ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody"
```

Dry-run fixture mode:

```bash
ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody" --dry-run
```

Registry usage after implementation:

```bash
ruby bin/soul skill youtube.video_resolve -- --query "Bohemian Rhapsody" --dry-run
```

## Relationship to youtube.song_search

```text
youtube.video_resolve
  query -> watch URL candidate

youtube.song_search
  watch URL -> browser launch after confirmation
```

The resolver exists because `youtube.song_search --query` intentionally opens search results and does not scrape YouTube to find a video ID.
