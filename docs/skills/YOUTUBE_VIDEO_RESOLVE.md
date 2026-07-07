# youtube.video_resolve

Implemented skill.

## Purpose

Resolve a song/search query to a YouTube video candidate using the official YouTube Data API v3.

The resolver returns candidate metadata and a direct YouTube watch URL.

It does not open the browser.

Opening remains the job of:

```text
youtube.song_search --url <watch_url>
```

## Required config for live mode

```text
YOUTUBE_DATA_API_KEY
```

The key may be supplied through `.env` or the shell environment.

The key must not be hardcoded, printed, or written to task logs.

## Dry-run mode

Dry-run mode does not require an API key and does not make a network call:

```bash
ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody" --dry-run
```

## Direct usage

Live mode:

```bash
ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody"
```

Alias:

```bash
ruby Soul/skills/youtube/video_resolve.rb --song "Miles Davis So What"
```

Limit candidates:

```bash
ruby Soul/skills/youtube/video_resolve.rb --query "Bohemian Rhapsody" --max-results 3
```

`--max-results` is clamped to a conservative range of 1..5.

## Registry usage

```bash
ruby bin/soul skill youtube.video_resolve -- --query "Bohemian Rhapsody" --dry-run
```

Live mode:

```bash
ruby bin/soul skill youtube.video_resolve -- --query "Bohemian Rhapsody"
```

## Output

Success includes:

```text
candidate.title
candidate.channel_title
candidate.video_id
candidate.watch_url
candidates[]
```

The resolver returns:

```text
complete
blocked_for_input
no_match
failed
```

## Boundary

The resolver does not:

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

The resolver is read-only from Soul/'s perspective. It makes a network request only in live API mode.

## Suggested chain

```text
youtube.video_resolve --query "Bohemian Rhapsody"
review candidate title/channel/watch URL
youtube.song_search --url <watch_url> --confirm
```

Future workflow integration should automate that chain while preserving the user confirmation step before browser launch.

## Verification

```bash
ruby scripts/verify-youtube-video-resolve.rb
```

The verifier uses dry-run mode and missing-key checks. It does not call the live YouTube API by default, because quota goblins must be starved whenever possible.

## Provider error diagnostics

Live API failures include a sanitized `provider_error` object when Google returns structured error details.

Possible fields:

```text
provider_error.message
provider_error.reason
provider_error.domain
provider_error.location
provider_error.location_type
```

These diagnostics are intended to make failures such as invalid API keys, disabled APIs, quota issues, or bad request parameters easier to understand.

The resolver must not print or log the API key. Provider diagnostics are sanitized before being returned or written to task logs.
