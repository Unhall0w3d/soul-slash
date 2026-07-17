# Music reference library A5 research and design review

## Candidate outcome

The prior Music A5 placeholder is now an implementable, bounded design for URL
evidence, artist/album/track profiles, component revisions, and coherent
multi-profile fusion. A5.1 implements only the private reference-library
foundation and dashboard inventory surface; URL retrieval remains unavailable
until A5.2 receives its own dependency and foreground-operation review.

## Research basis

- yt-dlp documents single-video metadata JSON, configuration isolation,
  playlist rejection, download limits, and frequently changing site support.
- Essentia documents Linux installation and extractors for rhythm, tonal,
  spectral, dynamics, and higher-level descriptors.
- MusicBrainz documents bounded JSON search/lookup for recording, release,
  release-group, and artist metadata.

Primary references:

- <https://github.com/yt-dlp/yt-dlp/blob/master/README.md>
- <https://github.com/yt-dlp/yt-dlp/releases>
- <https://essentia.upf.edu/installing.html>
- <https://essentia.upf.edu/streaming_extractor_music.html>
- <https://essentia.upf.edu/reference/std_RhythmExtractor2013.html>
- <https://essentia.upf.edu/reference/std_KeyExtractor.html>
- <https://musicbrainz.org/doc/MusicBrainz_API>
- <https://musicbrainz.org/doc/MusicBrainz_API/Search>

## Files changed

- `lib/soul_core/music_reference_library_store.rb`
- `lib/soul_core/music_reference_library_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `docs/soul/MUSIC_REFERENCE_LIBRARY_AND_URL_INGESTION_DESIGN.md`
- `docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md`
- `scripts/verify-music-reference-library-a5.rb`
- `Makefile`
- this review artifact

## Commands and deterministic results

- `ruby scripts/verify-music-reference-library-a5.rb` — passed.
- `make verify-music-references` — passed.
- `ruby scripts/verify-music-studio-a3.rb` — passed.
- `ruby scripts/verify-music-studio-a3-vocal-analysis.rb` — passed.
- `ruby scripts/verify-music-revision-draft.rb` — passed.
- `ruby scripts/verify-music-candidate-dispositions.rb` — passed.
- `node --check assets/dashboard/dashboard.js` — passed.
- `ruby -c lib/soul_core/music_reference_library_store.rb` — passed.
- `ruby -c lib/soul_core/application_facade.rb` — passed.
- `git diff --check` — passed.
- `systemctl --user restart soul-dashboard.service` followed by
  `systemctl --user is-active soul-dashboard.service` — active.

## Local LLM eval

Not run for A5.1. The foundation performs no model call or synthesis. Behavioral
evaluation belongs to A5.3.

## Memory and lifecycle

- Memory keys added or used: none. Reference profiles are private Music Studio
  domain artifacts, not durable personality memory.
- Lifecycle states touched: `complete`, `awaiting_input`, and
  `blocked_for_human_review` for deterministic store/inventory validation. A5.1
  adds no operation that can silently remain running.

## Risk classification

Moderate for the complete A5 design because later URL retrieval handles remote
media. Low for A5.1 because it adds only bounded local records and read-only UI.

## Known weaknesses

- A5.1 cannot analyze a URL, infer album metadata, generate synthesis, retry a
  component, or create a fusion.
- Artist/album grouping is limited to reviewed records already present locally.

## Human review checklist

- [ ] Confirm the library hierarchy and right-side placement are useful.
- [ ] Confirm analysis-only retention is the correct default.
- [ ] Confirm source measurements and target suggestions are visually distinct.
- [ ] Confirm fusion should support two to five selected profiles.
- [ ] Confirm A5.2 may add pinned optional yt-dlp and Essentia setup.
