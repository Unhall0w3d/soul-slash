# youtube.song_search

Implemented skill.

## Purpose

Open a YouTube search for a requested song/query in the default Linux browser after explicit confirmation.

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
bypass ads or access controls
start persistent Soul/ processes
store durable song history
make direct network requests
```

The browser may load YouTube after launch, but Soul/ itself only constructs the URL and launches the browser.

## Direct usage

Plan-only mode, which is the default unless `--confirm` is passed:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody"
```

Explicit plan-only mode:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --plan-only
```

Confirmed execution:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --confirm
```

Dry-run confirmed execution:

```bash
ruby Soul/skills/youtube/song_search.rb --query "Bohemian Rhapsody" --confirm --dry-run
```

## Registry usage

```bash
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --plan-only
```

```bash
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --confirm
```

## Inputs

```text
--query TEXT
--song TEXT
```

`--song` is an alias for `--query`.

The skill normalizes whitespace and rejects empty queries. Query length is capped at 240 characters.

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

Missing input outcome:

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

The verifier uses this so it does not open a real browser, because apparently tests opening browser tabs is frowned upon by civilized society.

## Verification

```bash
ruby scripts/verify-youtube-song-search.rb
```

The verifier checks direct invocation, URL encoding, dry-run behavior, fake launcher behavior, registry presence, and `bin/soul` invocation.
