# Soul/ YouTube Song Launcher Plan Overlay

This overlay adds the implementation plan for the reviewed YouTube song launcher proposal.

It does not implement the skill.

## Adds

```text
docs/implementation/YOUTUBE_SONG_LAUNCHER_PLAN.md
docs/skills/YOUTUBE_SONG_SEARCH.md
scripts/verify-youtube-song-launcher-plan.rb
README_YOUTUBE_SONG_LAUNCHER_PLAN.md
docs/overlays/README_YOUTUBE_SONG_LAUNCHER_PLAN.md
```

## Decision

Supported platform:

```text
Linux only
```

Initial launcher:

```text
xdg-open
```

Proposed skill name:

```text
youtube.song_search
```

The name is intentionally honest. It opens a YouTube search URL. It does not directly play audio, select a verified video, download media, scrape YouTube, or bypass ads.

## Apply

```bash
unzip ~/Downloads/soul_youtube_song_launcher_plan_overlay.zip
chmod +x scripts/verify-youtube-song-launcher-plan.rb
```

## Verify

```bash
ruby scripts/verify-youtube-song-launcher-plan.rb
```

Expected:

```text
Verification complete.
```

## Review

```bash
cat docs/implementation/YOUTUBE_SONG_LAUNCHER_PLAN.md
cat docs/skills/YOUTUBE_SONG_SEARCH.md
```

## Commit

```bash
git status --short
git add docs/implementation/YOUTUBE_SONG_LAUNCHER_PLAN.md \
  docs/skills/YOUTUBE_SONG_SEARCH.md \
  scripts/verify-youtube-song-launcher-plan.rb

git commit -m "Plan YouTube song search skill"
git push origin main
```

Under the current docs cleanup policy, do not commit the root overlay README unless you intentionally want it archived. The root `README_YOUTUBE_SONG_LAUNCHER_PLAN.md` exists as apply-time guidance.

## Next overlay

After human review, the next overlay should be:

```text
soul_youtube_song_search_skill_overlay.zip
```

It should implement:

```text
Soul/skills/youtube/song_search.rb
scripts/verify-youtube-song-search.rb
registry entry for youtube.song_search
docs/skills/YOUTUBE_SONG_SEARCH.md update from planned to implemented
```

The implementation verifier must not open a real browser. It should use a fake launcher or `SOUL_YOUTUBE_LAUNCHER`.
