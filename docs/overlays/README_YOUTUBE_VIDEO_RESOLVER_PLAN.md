# Soul/ YouTube Video Resolver Plan Overlay

This overlay adds the implementation plan for an optional YouTube video resolver.

It does not implement the resolver.

## Proposed skill

```text
youtube.video_resolve
```

## Why this exists

`youtube.song_search --query` opens YouTube search results.

`youtube.song_search --url` opens a direct YouTube watch URL.

The missing piece is:

```text
song/search query -> video ID/watch URL
```

That requires a resolver. The recommended first resolver uses the official YouTube Data API, not scraping, because apparently we are still trying to build something that will survive contact with reality.

## Adds

```text
docs/implementation/YOUTUBE_VIDEO_RESOLVER_PLAN.md
docs/skills/YOUTUBE_VIDEO_RESOLVE.md
scripts/verify-youtube-video-resolver-plan.rb
README_YOUTUBE_VIDEO_RESOLVER_PLAN.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVER_PLAN.md
```

## Key decision

Initial resolver provider:

```text
Official YouTube Data API v3
```

Required live-mode config:

```text
YOUTUBE_DATA_API_KEY
```

## Boundaries

The resolver must not:

```text
scrape YouTube
download media
extract streams
bypass ads or access controls
open the browser
select and launch without human confirmation
print or log API key values
run persistently
store durable song history
```

## Apply

```bash
unzip ~/Downloads/soul_youtube_video_resolver_plan_overlay.zip
chmod +x scripts/verify-youtube-video-resolver-plan.rb
```

## Verify

```bash
ruby scripts/verify-youtube-video-resolver-plan.rb
```

Expected:

```text
Verification complete.
```

## Review

```bash
cat docs/implementation/YOUTUBE_VIDEO_RESOLVER_PLAN.md
cat docs/skills/YOUTUBE_VIDEO_RESOLVE.md
```

## Commit

```bash
git status --short
git add docs/implementation/YOUTUBE_VIDEO_RESOLVER_PLAN.md \
  docs/skills/YOUTUBE_VIDEO_RESOLVE.md \
  scripts/verify-youtube-video-resolver-plan.rb

git commit -m "Plan YouTube video resolver skill"
git push origin main
```

Under the current docs cleanup policy, do not commit the root overlay README unless you intentionally archive it.

## Next overlay

After human review, the next overlay should be:

```text
soul_youtube_video_resolve_skill_overlay.zip
```

It should implement:

```text
Soul/skills/youtube/video_resolve.rb
scripts/verify-youtube-video-resolve.rb
registry entry for youtube.video_resolve
docs/skills/YOUTUBE_VIDEO_RESOLVE.md update from planned to implemented
```

The verifier must not call the live API by default. It should use dry-run fixture mode.
