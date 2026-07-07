# Soul/ YouTube Song Search Direct URL Overlay

This overlay upgrades `youtube.song_search` to support direct YouTube watch/share URLs.

## Why

The initial implementation opened YouTube search results for song-name queries. That was correct for the no-API/no-scrape boundary, but it does not autoplay a specific video.

Opening a video directly requires a YouTube watch URL:

```text
https://www.youtube.com/watch?v=<video_id>
```

This overlay adds safe direct URL support without scraping YouTube or pretending a plain song name magically identifies the right video. Apparently reality still insists on identifiers. Tiresome, but useful.

## Adds / updates

```text
scripts/patch-youtube-song-search-direct-url.rb
scripts/verify-youtube-song-search-direct-url.rb
docs/skills/YOUTUBE_SONG_SEARCH.md
README_YOUTUBE_SONG_SEARCH_DIRECT_URL.md
docs/overlays/README_YOUTUBE_SONG_SEARCH_DIRECT_URL.md
```

## Patches

```text
Soul/skills/youtube/song_search.rb
```

## New behavior

Search query mode still opens search results:

```bash
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --confirm
```

Direct URL mode opens a normalized watch URL:

```bash
ruby bin/soul skill youtube.song_search -- --url "https://youtu.be/dQw4w9WgXcQ" --confirm
```

Supported URL inputs:

```text
youtube.com/watch?v=<video_id>
music.youtube.com/watch?v=<video_id>
m.youtube.com/watch?v=<video_id>
youtu.be/<video_id>
youtube.com/shorts/<video_id>
```

Normalized output:

```text
https://www.youtube.com/watch?v=<video_id>
```

## Still not included

```text
no scraping
no downloading
no ad/access-control bypass
no song-name-to-video resolver
no YouTube Data API yet
```

A future resolver overlay can add optional official YouTube Data API support.

## Apply

```bash
unzip ~/Downloads/soul_youtube_song_search_direct_url_overlay.zip
chmod +x scripts/patch-youtube-song-search-direct-url.rb \
  scripts/verify-youtube-song-search-direct-url.rb

ruby scripts/patch-youtube-song-search-direct-url.rb
```

## Verify

```bash
ruby scripts/verify-youtube-song-search-direct-url.rb
```

Expected:

```text
Verification complete.
```

The verifier does not open a real browser.

## Manual plan test

```bash
ruby bin/soul skill youtube.song_search -- --url "https://youtu.be/dQw4w9WgXcQ"
```

Expected:

```text
awaiting_confirmation
```

## Manual confirmed launch

This opens your real browser:

```bash
ruby bin/soul skill youtube.song_search -- --url "https://youtu.be/dQw4w9WgXcQ" --confirm
```

## Cleanup before commit

```bash
rm scripts/patch-youtube-song-search-direct-url.rb
rm README_YOUTUBE_SONG_SEARCH_DIRECT_URL.md
rm docs/overlays/README_YOUTUBE_SONG_SEARCH_DIRECT_URL.md
rm -f Soul/logs/tasks/*-youtube.song_search.json
```

## Commit

```bash
git status --short
git add Soul/skills/youtube/song_search.rb \
  scripts/verify-youtube-song-search-direct-url.rb \
  docs/skills/YOUTUBE_SONG_SEARCH.md

git commit -m "Add direct YouTube URL support"
git push origin main
```

## Next recommended overlay

Plan an optional official YouTube Data API resolver:

```text
soul_youtube_video_resolver_plan_overlay.zip
```

That resolver would let song-name queries become user-confirmed watch URLs without scraping.
