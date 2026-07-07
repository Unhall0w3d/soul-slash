# Soul/ YouTube Video Resolve Error Detail Repair v2 Overlay

This is the less-brittle repair for the resolver diagnostic patch.

The previous script looked for an exact API failure block and failed when the local file did not match byte-for-byte. This version patches structurally:

```text
find unless response.is_a?(Net::HTTPSuccess)
replace that full block
replace api_failure_recommendation method
insert sanitized_provider_error/redact_secret helpers
```

## Adds

```text
scripts/patch-youtube-video-resolve-error-details-v2.rb
README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md
docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md
```

## Apply

```bash
unzip ~/Downloads/soul_youtube_video_resolve_error_detail_repair_v2_overlay.zip
chmod +x scripts/patch-youtube-video-resolve-error-details-v2.rb
ruby scripts/patch-youtube-video-resolve-error-details-v2.rb
```

The docs patch from v1 already ran. If needed, rerun it:

```bash
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

## Cleanup before commit

```bash
rm scripts/patch-youtube-video-resolve-error-details.rb 2>/dev/null || true
rm scripts/patch-youtube-video-resolve-error-docs.rb 2>/dev/null || true
rm scripts/patch-youtube-video-resolve-error-details-v2.rb
rm README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md 2>/dev/null || true
rm README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md
rm docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR.md 2>/dev/null || true
rm docs/overlays/README_YOUTUBE_VIDEO_RESOLVE_ERROR_DETAIL_REPAIR_V2.md
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
