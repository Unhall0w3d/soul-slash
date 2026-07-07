# Soul/ YouTube Song Search Skill Overlay

This overlay implements the Linux-only YouTube song search skill.

## Adds / updates

```text
Soul/skills/youtube/song_search.rb
scripts/patch-youtube-song-search-registry.rb
scripts/verify-youtube-song-search.rb
docs/skills/YOUTUBE_SONG_SEARCH.md
README_YOUTUBE_SONG_SEARCH_SKILL.md
docs/overlays/README_YOUTUBE_SONG_SEARCH_SKILL.md
```

## Skill

```text
youtube.song_search
```

## Supported platform

```text
Linux only
```

## Launcher

```text
xdg-open
```

## Safety boundary

The skill does not:

```text
download media
scrape YouTube
bypass ads or access controls
start persistent Soul/ processes
store durable song history
make direct network requests
```

## Apply

```bash
unzip ~/Downloads/soul_youtube_song_search_skill_overlay.zip
chmod +x Soul/skills/youtube/song_search.rb \
  scripts/patch-youtube-song-search-registry.rb \
  scripts/verify-youtube-song-search.rb

ruby scripts/patch-youtube-song-search-registry.rb
```

## Verify

```bash
ruby scripts/verify-youtube-song-search.rb
```

Expected:

```text
Verification complete.
```

The verifier does not open a real browser. It uses `--dry-run` and a fake launcher through `SOUL_YOUTUBE_LAUNCHER`.

## Manual plan

```bash
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --plan-only
```

## Manual confirmed launch

This will open the default Linux browser:

```bash
ruby bin/soul skill youtube.song_search -- --query "Bohemian Rhapsody" --confirm
```

## Cleanup before commit

Remove patch scaffolding and root overlay README:

```bash
rm scripts/patch-youtube-song-search-registry.rb
rm README_YOUTUBE_SONG_SEARCH_SKILL.md
rm docs/overlays/README_YOUTUBE_SONG_SEARCH_SKILL.md
```

Clean generated task logs:

```bash
rm -f Soul/logs/tasks/*-youtube.song_search.json
```

## Commit

```bash
git status --short
git add Soul/skills/youtube/song_search.rb \
  Soul/skills/registry.yaml \
  scripts/verify-youtube-song-search.rb \
  docs/skills/YOUTUBE_SONG_SEARCH.md

git commit -m "Add YouTube song search skill"
git push origin main
```

## Next overlay

After this direct skill is stable, add natural intent/workflow integration so users can say:

```text
play Bohemian Rhapsody on YouTube
```

and Soul/ stages the plan before opening the browser.
