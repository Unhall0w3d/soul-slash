# YouTube Song Launcher Implementation Plan

## Status

```text
implementation_plan
```

This document converts the reviewed skill proposal into a concrete implementation plan for Soul/.

It does not implement the skill.

## Proposed skill name

```text
youtube.song_search
```

This name is intentionally precise. The first supported behavior is not direct audio playback. The skill opens a YouTube search URL in the default Linux browser and lets YouTube/browser behavior handle the rest.

Calling it `youtube.play_song` would overpromise. Tiny wording choices, unfortunately, are where bugs breed.

## Supported platform

```text
Linux only
```

Initial implementation must support Linux desktop environments through:

```text
xdg-open
```

No Windows support is planned.

No macOS support is planned.

## Purpose

Allow the user to ask Soul/ to play a requested song on YouTube by opening a bounded YouTube search URL in the user's default browser.

The skill must:

```text
accept a song/search query
validate that the query is non-empty
construct a YouTube search URL
produce a plan artifact/result before launch
require explicit user confirmation before opening the browser
launch with xdg-open after confirmation
report verified completion/failure/cancellation
write a task log
avoid scraping/downloading/ad-bypass behavior
exit after browser launch attempt
```

## Explicit non-goals

The first implementation must not:

```text
download media
extract audio/video streams
scrape YouTube pages
use unofficial YouTube APIs
bypass ads or access controls
pick a specific video without user review
run persistently
poll browser state
store song history durably
support Windows
support macOS
```

## Proposed files for implementation overlay

```text
Soul/skills/youtube/song_search.rb
scripts/verify-youtube-song-search.rb
docs/skills/YOUTUBE_SONG_SEARCH.md
docs/implementation/YOUTUBE_SONG_LAUNCHER_PLAN.md
```

Optional later files:

```text
Soul/workflows/youtube_song_search.json
docs/evals/YOUTUBE_SONG_SEARCH_EVALS.md
```

## Invocation shape

Direct skill invocation:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody"
```

Plan-only mode:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --plan-only
```

Confirmed execution:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --confirm
```

Registry invocation after integration:

```bash
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --plan-only
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --confirm
```

Natural workflow integration should come after the direct skill is stable:

```bash
ruby bin/soul do "play Bohemian Rhapsody on YouTube"
ruby bin/soul respond "yes"
```

## Inputs

Required:

```text
query
```

Accepted aliases:

```text
--query
--song
```

Optional flags:

```text
--plan-only
--confirm
--dry-run
```

Input validation:

```text
trim leading/trailing whitespace
collapse repeated whitespace
reject empty query
reject query over a conservative maximum length, suggested 240 characters
do not interpret shell syntax
do not execute user-provided text
URL-encode query before constructing URL
```

## URL construction

The implementation should use Ruby standard library escaping, for example:

```text
URI.encode_www_form_component(query)
```

Target URL:

```text
https://www.youtube.com/results?search_query=<encoded_query>
```

No scraping is needed. No preflight web request is needed.

## Execution behavior

Use Linux `xdg-open`.

The implementation should check:

```text
xdg-open is present in PATH
```

Then execute the browser launch as an argument array, not a shell string.

Preferred Ruby execution approach:

```text
Open3.capture3("xdg-open", url)
```

or:

```text
system("xdg-open", url)
```

Do not use:

```text
system("xdg-open #{url}")
```

because shell interpolation of user-derived text is how computers become crime scenes.

## Lifecycle states

The skill should return JSON with one of these terminal states:

```text
complete
blocked_for_input
canceled
failed
```

Suggested lifecycle:

```text
invoked
validated
planned
awaiting_confirmation
executing
complete
blocked_for_input
canceled
failed
```

## Confirmation model

Direct skill mode:

```text
--plan-only
```

returns the URL and a recommendation that confirmation is required.

```text
--confirm
```

executes immediately after validation.

When the natural workflow is added later, the workflow should hold the pending plan and require the user to explicitly confirm with a response such as:

```text
yes
open it
do it
```

The skill itself should remain deterministic and should not conduct a conversational confirmation loop internally unless that pattern already exists in the framework.

## Output JSON shape

Plan-only example:

```json
{
  "skill": "youtube.song_search",
  "status": "ok",
  "outcome": "awaiting_confirmation",
  "query": "Bohemian Rhapsody",
  "url": "https://www.youtube.com/results?search_query=Bohemian+Rhapsody",
  "recommendation": "Review the YouTube search URL and confirm before opening the browser.",
  "verification": {
    "read_only": true,
    "network_used": false,
    "browser_launch_attempted": false,
    "download_attempted": false,
    "scraping_attempted": false,
    "complete": false,
    "final_state": "awaiting_confirmation"
  }
}
```

Confirmed success example:

```json
{
  "skill": "youtube.song_search",
  "status": "ok",
  "outcome": "complete",
  "query": "Bohemian Rhapsody",
  "url": "https://www.youtube.com/results?search_query=Bohemian+Rhapsody",
  "launcher": "xdg-open",
  "recommendation": "YouTube search opened in the default browser.",
  "verification": {
    "read_only": false,
    "network_used": false,
    "browser_launch_attempted": true,
    "download_attempted": false,
    "scraping_attempted": false,
    "complete": true,
    "final_state": "complete"
  }
}
```

Important nuance:

```text
network_used
```

should remain false because the skill itself does not make a network request. The browser may make network requests after launch, but that happens outside Soul/'s process.

## Logging

Write task logs under:

```text
Soul/logs/tasks/
```

Suggested filename pattern:

```text
<timestamp>-youtube.song_search.json
```

Do not log:

```text
browser cookies
browser profile paths
YouTube account details
search history beyond the current requested query
```

Logging the current query and constructed URL is acceptable because they are explicit task inputs/outputs.

## Registry entry

The implementation overlay should add:

```yaml
youtube.song_search:
  description: "Open a YouTube search for a requested song in the default Linux browser after confirmation."
  path: "Soul/skills/youtube/song_search.rb"
  script: "Soul/skills/youtube/song_search.rb"
  entrypoint: "Soul/skills/youtube/song_search.rb"
  command: "ruby Soul/skills/youtube/song_search.rb"
  read_only: false
  network: false
  risk: "low"
  category: "media"
```

The exact shape must match the current registry format.

Even though the skill opens a browser, it does not mutate files, delete data, access secrets, or make direct network calls. `risk: low` is appropriate.

## Deterministic verifier requirements

The implementation overlay must include:

```text
scripts/verify-youtube-song-search.rb
```

It should test:

```text
help output works
empty query returns blocked_for_input
whitespace query returns blocked_for_input
plan-only with query returns awaiting_confirmation
URL encodes spaces and special characters correctly
dry-run confirmed mode does not call xdg-open
confirmed mode can be tested using a fake launcher command
JSON shape includes verification fields
download_attempted is false
scraping_attempted is false
```

The verifier must not open a real browser.

To avoid opening a real browser, implementation should support an internal test-only environment variable such as:

```text
SOUL_YOUTUBE_LAUNCHER
```

Default:

```text
xdg-open
```

Verifier can set:

```text
SOUL_YOUTUBE_LAUNCHER=/bin/true
```

or use a temporary fake executable.

## Local LLM evals

Suggested future eval prompts:

```text
play Bohemian Rhapsody on YouTube
open YouTube and play Miles Davis So What
play the song Hurt by Johnny Cash on YouTube
YouTube Search for Sultans of Swing
play on YouTube
```

Expected routing:

```text
queries with song names route to youtube.song_search plan
missing song name asks for input
implementation never claims it selected the correct video
implementation never claims playback started unless browser launch was attempted successfully
```

## Reflection candidates

The implementation should stage reflection candidates only for useful failures, such as:

```text
xdg-open missing
browser launch command failed
natural language routing repeatedly misses YouTube song requests
```

No reflection should be staged merely because a user searched for a song.

## Implementation sequence

1. Add direct Ruby skill.
2. Add deterministic verifier.
3. Add docs.
4. Register skill.
5. Verify direct skill and bin/soul skill invocation.
6. Add natural workflow/intent routing in a later overlay.
7. Add evals/reflection handling after route behavior is observed.

## Human approval gate

This plan is ready for human review.

Implementation should not proceed unless the user explicitly approves moving from plan to implementation.
