# YouTube Play Workflow

## Intent

```text
youtube.play
```

## Purpose

Let the user ask Soul/ to play a song on YouTube using a safe, confirmation-gated workflow.

Target request:

```bash
ruby bin/soul do "play Bohemian Rhapsody on YouTube"
```

## Flow

```text
natural request
-> deterministic intent route: youtube.play
-> extract song/search query
-> youtube.video_resolve
-> show title/channel/watch URL
-> wait for confirmation
-> youtube.song_search --url <watch_url> --confirm
-> report complete
```

## Confirmation

The workflow must stop before browser launch and ask the user to confirm.

Example:

```bash
ruby bin/soul respond "yes"
```

Cancel:

```bash
ruby bin/soul respond "cancel"
```

## Resolver fallback

If `youtube.video_resolve` cannot return a candidate, the workflow stages a fallback option:

```text
open YouTube search results instead
```

That fallback still requires confirmation before browser launch.

## Environment

Live resolver mode requires:

```text
YOUTUBE_DATA_API_KEY
```

The verifier uses:

```text
SOUL_YOUTUBE_PLAY_DRY_RUN=1
SOUL_YOUTUBE_LAUNCHER=<fake launcher>
```

so it does not call the live YouTube API and does not open a real browser.

## Boundaries

The workflow does not:

```text
open the browser before confirmation
download media
scrape YouTube
bypass ads or access controls
claim playback started
guarantee autoplay
store durable listening history
```

It may say that Soul opened the watch URL. Browser playback, autoplay, and ads are outside Soul's control.

## Commands

Plan and confirm with dry-run resolver:

```bash
SOUL_YOUTUBE_PLAY_DRY_RUN=1 ruby bin/soul do "play Bohemian Rhapsody on YouTube"
ruby bin/soul respond "yes"
```

Live resolver:

```bash
ruby bin/soul do "play Bohemian Rhapsody on YouTube"
ruby bin/soul respond "yes"
```

## Verification

```bash
ruby scripts/verify-youtube-play-workflow.rb
```
