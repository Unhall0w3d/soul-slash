# Soul/ YouTube Video Resolve Skill Overlay

This overlay implements the optional YouTube video resolver skill.

## Adds / updates

```text
Soul/skills/youtube/video_resolve.rb
scripts/patch-youtube-video-resolve-registry.rb
scripts/verify-youtube-video-resolve.rb
docs/skills/YOUTUBE_VIDEO_RESOLVE.md
README_YOUTUBE_VIDEO_RESOLVE_SKILL.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_SKILL.md
```

## Skill

```text
youtube.video_resolve
```

## Purpose

Resolve a song/search query to a YouTube video candidate using the official YouTube Data API v3.

It returns:

```text
title
channel title
video ID
watch URL
```

It does not open the browser. Browser launch remains:

```text
youtube.song_search --url <watch_url>
```

## Required config for live mode

```text
YOUTUBE_DATA_API_KEY
```

This can be in `.env` or shell environment.

Do not commit it. Do not print it. Do not feed it to the repo gods.

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

## Apply

```bash
unzip ~/Downloads/soul_youtube_video_resolve_skill_overlay.zip
chmod +x Soul/skills/youtube/video_resolve.rb \
  scripts/patch-youtube-video-resolve-registry.rb \
  scripts/verify-youtube-video-resolve.rb

ruby scripts/patch-youtube-video-resolve-registry.rb
```

## Verify

```bash
ruby scripts/verify-youtube-video-resolve.rb
```

Expected:

```text
Verification complete.
```

The verifier does not call the live YouTube API by default.

## Dry-run test

```bash
ruby bin/soul skill youtube.video_resolve -- --query "Bohemian Rhapsody" --dry-run
```

## Live test

Requires `YOUTUBE_DATA_API_KEY`:

```bash
ruby bin/soul skill youtube.video_resolve -- --query "Bohemian Rhapsody"
```

## Chain with browser launch

After reviewing the resolver candidate:

```bash
ruby bin/soul skill youtube.song_search -- --url "<watch_url>" --confirm
```

## Cleanup before commit

```bash
rm scripts/patch-youtube-video-resolve-registry.rb
rm README_YOUTUBE_VIDEO_RESOLVE_SKILL.md
rm docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_SKILL.md
find Soul/logs/tasks -type f -name '*-youtube.video_resolve.json' -delete
```

## Commit

```bash
git status --short
git add Soul/skills/youtube/video_resolve.rb \
  Soul/skills/registry.yaml \
  scripts/verify-youtube-video-resolve.rb \
  docs/skills/YOUTUBE_VIDEO_RESOLVE.md

git commit -m "Add YouTube video resolver skill"
git push origin main
```

## Next overlay

After direct resolver testing, add natural workflow integration:

```text
play Bohemian Rhapsody on YouTube
```

Expected flow:

```text
resolve candidate
show title/channel/watch URL
ask confirmation
open watch URL through youtube.song_search
```
