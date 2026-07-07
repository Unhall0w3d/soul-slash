# YouTube Video Resolver Implementation Plan

## Status

```text
implementation_plan
```

This document defines the plan for adding an optional YouTube video resolver to Soul/.

It does not implement the resolver.

## Proposed skill name

```text
youtube.video_resolve
```

This should be a separate skill rather than hidden inside `youtube.song_search`.

Reason:

```text
youtube.video_resolve
  query -> candidate watch URL

youtube.song_search
  direct URL -> open browser after confirmation
```

Small skills chain cleanly. Big skills become soup with command-line flags.

## Purpose

Resolve a user-provided song/search query into a YouTube video candidate using an official API-backed search path.

The resolver should return:

```text
video title
channel title
video ID
watch URL
provider/source
confidence/relevance notes, if available
```

It must not open the browser. Opening remains the job of:

```text
youtube.song_search --url <watch_url>
```

## Supported platform

```text
Linux only for the full playback workflow
```

The resolver itself is platform-neutral Ruby code, but the Soul/ YouTube playback path is Linux-only because browser launch is handled by `youtube.song_search` through `xdg-open`.

## Resolver provider

Recommended initial provider:

```text
Official YouTube Data API v3
```

Required local config:

```text
YOUTUBE_DATA_API_KEY
```

The API key may be loaded from:

```text
.env
shell environment
```

Do not hardcode it.

Do not print it.

Do not write it to task logs.

## Why official API

The resolver needs a stable way to turn:

```text
Bohemian Rhapsody
```

into:

```text
https://www.youtube.com/watch?v=<video_id>
```

Without an API, the alternatives are:

```text
scraping YouTube HTML
using unofficial search endpoints
using downloader tools like yt-dlp
using search-engine redirect tricks
guessing
```

These are not acceptable for the first resolver implementation.

## Explicit non-goals

The resolver must not:

```text
scrape YouTube pages
download media
extract streams
bypass ads or access controls
log API key values
open a browser
select and launch without human confirmation
store durable listening/search history
run persistently
poll YouTube
use unofficial APIs as the default
```

## Proposed files for implementation overlay

```text
Soul/skills/youtube/video_resolve.rb
scripts/verify-youtube-video-resolve.rb
docs/skills/YOUTUBE_VIDEO_RESOLVE.md
docs/implementation/YOUTUBE_VIDEO_RESOLVER_PLAN.md
```

Optional later files:

```text
Soul/workflows/youtube_play_resolved.json
docs/evals/YOUTUBE_VIDEO_RESOLVE_EVALS.md
```

## Invocation shape

Direct resolver invocation:

```bash
ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody"
```

Dry-run fixture mode:

```bash
ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody" --dry-run
```

Registry invocation after integration:

```bash
ruby bin/soul skill youtube.video_resolve -- --query "Bohemian Rhapsody"
```

Expected later workflow:

```bash
ruby bin/soul do "play Bohemian Rhapsody on YouTube"
```

High-level workflow:

```text
extract query
resolve query with youtube.video_resolve
show selected candidate title/channel/watch URL
ask for confirmation
open via youtube.song_search --url <watch_url> --confirm
```

## Inputs

Required:

```text
--query TEXT
```

Accepted alias:

```text
--song TEXT
```

Optional flags:

```text
--dry-run
--max-results N
```

Input validation:

```text
trim leading/trailing whitespace
collapse repeated whitespace
reject empty query
reject query over 240 characters
cap max-results to a conservative range, suggested 1..5
do not execute user text
do not interpret shell syntax
```

## API request shape

Use YouTube Data API search endpoint with:

```text
part=snippet
type=video
q=<query>
maxResults=<N>
safeSearch=none or moderate, to be decided during implementation
videoEmbeddable=any
```

The exact Ruby implementation should use standard library HTTP unless the repo already has a preferred HTTP helper.

Potential standard-library stack:

```text
Net::HTTP
URI
JSON
```

The implementation should not add a gem dependency unless there is a strong reason.

## Output JSON shape

Success example:

```json
{
  "skill": "youtube.video_resolve",
  "status": "ok",
  "outcome": "complete",
  "query": "Bohemian Rhapsody",
  "provider": "youtube_data_api",
  "candidate": {
    "title": "Queen – Bohemian Rhapsody (Official Video Remastered)",
    "channel_title": "Queen Official",
    "video_id": "fJ9rUzIMcZQ",
    "watch_url": "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
  },
  "candidates": [
    {
      "rank": 1,
      "title": "Queen – Bohemian Rhapsody (Official Video Remastered)",
      "channel_title": "Queen Official",
      "video_id": "fJ9rUzIMcZQ",
      "watch_url": "https://www.youtube.com/watch?v=fJ9rUzIMcZQ"
    }
  ],
  "recommendation": "Review the resolved YouTube video candidate before opening it.",
  "verification": {
    "read_only": true,
    "network_used": true,
    "browser_launch_attempted": false,
    "download_attempted": false,
    "scraping_attempted": false,
    "ad_bypass_attempted": false,
    "api_key_values_printed": false,
    "complete": true,
    "final_state": "complete"
  }
}
```

Missing key example:

```json
{
  "skill": "youtube.video_resolve",
  "status": "warning",
  "outcome": "blocked_for_input",
  "recommendation": "YOUTUBE_DATA_API_KEY is required for live resolution. Use --dry-run for verifier fixtures.",
  "verification": {
    "read_only": true,
    "network_used": false,
    "browser_launch_attempted": false,
    "api_key_values_printed": false,
    "complete": false,
    "final_state": "blocked_for_input"
  }
}
```

No result example:

```json
{
  "skill": "youtube.video_resolve",
  "status": "warning",
  "outcome": "no_match",
  "query": "some unlikely query",
  "candidates": [],
  "recommendation": "No video candidate was returned. Try a more specific query or use youtube.song_search search mode.",
  "verification": {
    "read_only": true,
    "network_used": true,
    "browser_launch_attempted": false,
    "complete": false,
    "final_state": "no_match"
  }
}
```

## Lifecycle states

Suggested lifecycle:

```text
invoked
validated
blocked_for_input
resolving
complete
no_match
failed
```

The resolver must not produce:

```text
opened
playing
autoplay_confirmed
```

because it does not open the browser and cannot verify playback. Words are not confetti. We don't throw them around just because the room feels empty.

## Logging

Write task logs under:

```text
Soul/logs/tasks/
```

Suggested filename pattern:

```text
<timestamp>-youtube.video_resolve.json
```

Logs may include:

```text
query
provider name
HTTP status
candidate metadata
watch URLs
result count
terminal state
```

Logs must not include:

```text
YOUTUBE_DATA_API_KEY value
Authorization headers
full raw request URL with key parameter
browser cookies
YouTube account data
durable song history beyond the current task log
```

If the API key must be sent as a query parameter to the API endpoint, the logged URL must redact it.

## Registry entry

The implementation overlay should add:

```yaml
youtube.video_resolve:
  description: "Resolve a song/search query to a YouTube video candidate using the official YouTube Data API."
  path: "Soul/skills/youtube/video_resolve.rb"
  script: "Soul/skills/youtube/video_resolve.rb"
  entrypoint: "Soul/skills/youtube/video_resolve.rb"
  command: "ruby Soul/skills/youtube/video_resolve.rb"
  read_only: true
  network: true
  risk: "low"
  category: "media"
```

The exact shape must match the current registry.

## Deterministic verifier requirements

The implementation overlay must include:

```text
scripts/verify-youtube-video-resolve.rb
```

The verifier should not call the live YouTube API by default.

It should test:

```text
help output works
missing query returns blocked_for_input
missing YOUTUBE_DATA_API_KEY blocks live mode
dry-run fixture returns complete with candidate
candidate watch URL has youtube.com/watch?v=
API key value is not printed
JSON shape includes verification fields
browser_launch_attempted is false
download_attempted is false
scraping_attempted is false
registry entry includes youtube.video_resolve and risk
bin/soul invocation works in dry-run mode
```

Optional implementation test hook:

```text
SOUL_YOUTUBE_RESOLVE_FIXTURE
```

or simply:

```text
--dry-run
```

The dry-run fixture should return a realistic but static candidate.

## Future workflow integration

After direct resolver implementation is stable, add a workflow overlay.

Target natural request:

```text
play Bohemian Rhapsody on YouTube
```

Expected flow:

```text
1. Intent detects YouTube play request.
2. Workflow extracts query.
3. Workflow calls youtube.video_resolve.
4. Workflow displays candidate title/channel/watch URL.
5. Workflow asks user to confirm opening that video.
6. On confirmation, workflow calls youtube.song_search --url <watch_url> --confirm.
7. Workflow reports complete/failed with evidence.
```

If resolver is not configured:

```text
YOUTUBE_DATA_API_KEY missing
```

fallback should be:

```text
offer search-results mode through youtube.song_search --query
```

not:

```text
scrape YouTube
guess video ID
open first result invisibly
```

## Local LLM evals

Suggested prompts:

```text
play Bohemian Rhapsody on YouTube
play Hurt by Johnny Cash on YouTube
open YouTube and play Miles Davis So What
play Sultans of Swing
play on YouTube
```

Expected behavior:

```text
with song name and resolver configured: resolve candidate, ask confirmation
with missing song name: ask for the song name
with missing resolver API key: offer search-results fallback
never claim playback started unless browser launch skill completed
never claim correct video selection without showing candidate evidence
```

## Open questions for implementation

1. Should `safeSearch` be `none` or `moderate`?
2. Should max results default to `1` or return up to `3` candidates for user selection?
3. Should the resolver bias official channels? If yes, by documentation only at first, not opaque ranking magic.
4. Should the natural workflow always show the candidate before opening? Recommendation: yes.
5. Should API quota errors stage a reflection candidate? Recommendation: yes, only for repeated quota/rate failures.

## Recommended initial implementation choices

```text
safeSearch=none
maxResults=1
show title/channel/watch URL before opening
require confirmation before browser launch
do not rank beyond API result order
fallback to youtube.song_search query mode if API key is missing
```

## Human approval gate

This plan is ready for human review.

Implementation should not proceed unless the user explicitly approves moving from resolver plan to resolver implementation.
