# youtube.song_search

Planned skill.

## Purpose

Open a YouTube search for a requested song in the default Linux browser after explicit confirmation.

## Supported platform

```text
Linux only
```

The implementation is expected to use:

```text
xdg-open
```

No Windows or macOS support is planned.

## Current status

```text
planned
```

This skill is not implemented by this document. See:

```text
docs/implementation/YOUTUBE_SONG_LAUNCHER_PLAN.md
```

## Intended behavior

```text
user provides song/search query
Soul/ constructs a YouTube search URL
Soul/ asks for confirmation
confirmed execution opens the URL using xdg-open
Soul/ reports completion/failure/cancellation
```

## Safety boundary

The skill must not:

```text
download media
scrape YouTube
bypass ads or access controls
run persistently
store durable song history
make direct network requests
```

The browser may load YouTube after `xdg-open`, but Soul/ itself should only launch the URL.
