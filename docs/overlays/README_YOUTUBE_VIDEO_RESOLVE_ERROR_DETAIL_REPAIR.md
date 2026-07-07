# Soul/ YouTube Video Resolve Error Detail Repair Overlay

This overlay improves diagnostics for live YouTube Data API failures in:

```text
youtube.video_resolve
```

## Why

A mistyped API key returned HTTP 400, but the resolver only reported a generic message. That is technically correct and practically useless, the classic two-for-one of software disappointment.

The resolver should surface sanitized provider error details without leaking secrets.

## Adds

```text
scripts/patch-youtube-video-resolve-error-details.rb
scripts/patch-youtube-video-resolve-error-docs.rb
scripts/verify-youtube-video-resolve-error-details.rb
README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md
```

## Patches

```text
Soul/skills/youtube/video_resolve.rb
docs/skills/YOUTUBE_VIDEO_RESOLVE.md
```

## New diagnostic fields

On live API failure, the resolver may include:

```text
provider_error.message
provider_error.reason
provider_error.domain
provider_error.location
provider_error.location_type
```

## Safety boundary

The repair preserves:

```text
no API key printing
no API key logging
no full request URL logging
api_key_values_printed: false
api_key_logged: false
```

The resolver already avoids logging the full request URL because Google API keys are query parameters for this API call. Humanity chose this. We endure.

## Apply

```bash
unzip ~/Downloads/soul_youtube_video_resolve_error_detail_repair_overlay.zip
chmod +x scripts/patch-youtube-video-resolve-error-details.rb \
  scripts/patch-youtube-video-resolve-error-docs.rb \
  scripts/verify-youtube-video-resolve-error-details.rb

ruby scripts/patch-youtube-video-resolve-error-details.rb
ruby scripts/patch-youtube-video-resolve-error-docs.rb
```

## Verify

```bash
ruby scripts/verify-youtube-video-resolve-error-details.rb
ruby scripts/verify-youtube-video-resolve.rb
```

Expected:

```text
Verification complete.
```

## Optional live sanity test

With your corrected key:

```bash
ruby bin/soul skill youtube.video_resolve -- --query "Bohemian Rhapsody"
```

Expected:

```text
status: ok
outcome: complete
candidate.watch_url present
```

## Cleanup before commit

```bash
rm scripts/patch-youtube-video-resolve-error-details.rb
rm scripts/patch-youtube-video-resolve-error-docs.rb
rm README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md
rm docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md
find Soul/logs/tasks -type f -name '*-youtube.video_resolve.json' -delete
```

## Commit

```bash
git status --short
git add Soul/skills/youtube/video_resolve.rb \
  docs/skills/YOUTUBE_VIDEO_RESOLVE.md \
  scripts/verify-youtube-video-resolve-error-details.rb

git commit -m "Improve YouTube resolver error diagnostics"
git push origin main
```

## Next overlay

After this lands, build the natural workflow:

```text
play Bohemian Rhapsody on YouTube
```

Flow:

```text
resolve candidate
show title/channel/watch URL
ask confirmation
open watch URL through youtube.song_search
```
