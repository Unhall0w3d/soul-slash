# youtube.song_search

Implemented skill.

## Purpose

Open either:

```text
a YouTube search URL for a requested song/query
a normalized direct YouTube watch URL when the user provides one
```

in the default Linux browser after explicit confirmation.

## Supported platform

```text
Linux only
```

The skill uses:

```text
xdg-open
```

No Windows or macOS support is planned.

## Boundary

The skill does not:

```text
download media
scrape YouTube
resolve song-name searches to video IDs
bypass ads or access controls
start persistent Soul/ processes
store durable song history
make direct network requests
```

The browser may load YouTube after launch, but Soul/ itself only constructs or normalizes the URL and launches the browser.

## Important behavior distinction

Song/search query mode:

```text
--query "Bohemian Rhapsody"
```

opens:

```text
https://www.youtube.com/results?search_query=Bohemian+Rhapsody
```

Direct URL mode:

```text
--url "https://youtu.be/dQw4w9WgXcQ"
```

normalizes to and opens:

```text
https://www.youtube.com/watch?v=dQw4w9WgXcQ
```

The skill does not resolve song-name searches to video IDs. The skill cannot deterministically turn a plain song name into the correct watch URL without a resolver, such as an optional official YouTube Data API integration. It will not scrape YouTube to guess one, because apparently we are trying to build a tool instead of a tiny compliance bonfire.

## Accepted direct URL formats

```text
https://www.youtube.com/watch?v=<video_id>
https://youtube.com/watch?v=<video_id>
https://m.youtube.com/watch?v=<video_id>
https://music.youtube.com/watch?v=<video_id>
https://youtu.be/<video_id>
https://youtube.com/shorts/<video_id>
```

All accepted direct URL formats normalize to:

```text
https://www.youtube.com/watch?v=<video_id>
```

## Direct usage

Search query plan:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody"
```

Search query confirmed launch:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --confirm
```

Direct URL plan:

```bash
ruby Soul/skills/youtube/song_search.rb --url "https://youtu.be/dQw4w9WgXcQ"
```

Direct URL confirmed launch:

```bash
ruby Soul/skills/youtube/song_search.rb --url "https://youtu.be/dQw4w9WgXcQ" --confirm
```

Dry-run confirmed execution:

```bash
ruby Soul/skills/youtube/song_search.rb --url "https://youtu.be/dQw4w9WgXcQ" --confirm --dry-run
```

## Registry usage

```bash
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --plan-only
```

```bash
ruby bin/soul skill youtube.song_search -- --url "https://youtu.be/dQw4w9WgXcQ" --confirm
```

## Inputs

```text
--query TEXT
--song TEXT
--url URL
```

`--song` is an alias for `--query`.

If `--url` is present, URL mode takes precedence over query mode.

## Output

The skill returns JSON.

Plan-only outcome:

```text
awaiting_confirmation
```

Confirmed success outcome:

```text
complete
```

Missing or invalid input outcome:

```text
blocked_for_input
```

Launcher failure outcome:

```text
failed
```

## Launcher override

The default launcher is:

```text
xdg-open
```

For tests, set:

```bash
SOUL_YOUTUBE_LAUNCHER=/path/to/fake-launcher
```

The verifier uses this so it does not open a real browser.

## Verification

```bash
ruby scripts/verify-youtube-song-search-direct-url.rb
```

The verifier checks URL mode, URL normalization, invalid URL blocking, preserved search-query mode, fake launcher behavior, and docs.
