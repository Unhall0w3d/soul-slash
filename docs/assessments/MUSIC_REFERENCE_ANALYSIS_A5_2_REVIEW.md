# Music reference analysis A5.2 review

## Candidate outcome

Music Studio now exposes a bounded YouTube reference-analysis gate. It performs
a metadata-only preview, binds the exact source and limits to a digest, and
requires `ANALYZE_MUSIC_REFERENCE` before retrieving media. The confirmed
foreground request extracts deterministic tempo, tonal, dynamics, and energy
evidence into the private reference library, then removes the source media and
analysis WAV. It creates no service, queue, watcher, resident model, or
background continuation.

## What was implemented

- Strict HTTPS YouTube single-video URL parsing; playlists, credentials, custom
  ports, fragments, live/upcoming sources, and videos over 15 minutes fail
  before media retrieval.
- yt-dlp invocation isolated from user configuration, plugins, remote
  components, caches, cookies, playlists, infinite retries, and concurrency.
- A 250 MiB yt-dlp limit plus an OS child-process file-size limit.
- Bounded FFmpeg mono PCM conversion and project-owned Essentia extraction.
- Exact preview/digest/confirmation binding and NDJSON progress in Music Studio.
- Analysis-only retention: provenance and non-expressive evidence are stored;
  source media and raw transcription are never retained.
- Optional exact-gated `uv` setup that reuses a system yt-dlp when present and
  installs pinned Essentia (plus a pinned yt-dlp fallback only when needed),
  with automatic Python downloads disabled, no system Python mutation, and a
  resolved package receipt.

## Files changed

- `lib/soul_core/music_reference_analysis_service.rb`
- `lib/soul_core/music_generation_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `scripts/soul-music-reference-analyze`
- `scripts/soul-music-reference-tooling`
- `scripts/verify-music-reference-analysis-a5.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `Makefile`
- `docs/GETTING_STARTED.md`
- `docs/REQUIREMENTS.md`
- this review artifact

## Commands and deterministic results

- `make verify-music-reference-analysis` — passed.
- `ruby scripts/verify-music-reference-library-a5.rb` — passed.
- `ruby scripts/verify-music-studio-a3.rb` — passed.
- `ruby scripts/verify-music-studio-a3-vocal-analysis.rb` — passed.
- `ruby scripts/verify-music-revision-draft.rb` — passed.
- `ruby scripts/verify-music-candidate-dispositions.rb` — passed.
- `node --check assets/dashboard/dashboard.js` — passed.
- Ruby syntax checks for the service and setup command — passed.
- `make music-reference-tooling-check` — completed; tooling is not installed,
  while `/usr/bin/yt-dlp` 2026.07.04, `/usr/bin/uv`, and `/usr/bin/ffmpeg`
  are available.
- `make music-reference-tooling-plan` — blocked for human review as designed;
  current Essentia-only digest
  `136afa4ff7d284409dd2de4af3b763f5cdd762c51aa09323030c4eca467c53f1`.
- Exact-confirmed `make music-reference-tooling-install` — completed after the
  installer was corrected to validate both the PyPI distribution version
  `2.1b6.dev1438` and Essentia runtime identity `2.1-beta6-dev`; system yt-dlp
  `2026.07.04` was reused and not duplicated.
- A generated eight-second 44.1 kHz mono WAV smoke test through the installed
  analyzer — completed; produced bounded rhythm, tonal, dynamics, danceability,
  and eight-segment energy evidence, then the temporary WAV was removed.
- `git diff --check` — passed.
- Dashboard service restart and active-state check — active.

## Research basis

- yt-dlp's official documentation defines configuration isolation,
  single-JSON metadata, playlist rejection, socket timeouts, finite retries,
  download-size limits, disabled plugins/remote components, and stable/nightly
  release behavior.
- Essentia's official documentation defines PyPI installation and its rhythm
  and key extractors. PyPI publishes CPython 3.14 Linux wheels for the pinned
  current build.

Primary sources:

- <https://github.com/yt-dlp/yt-dlp/blob/master/README.md>
- <https://pypi.org/simple/yt-dlp/>
- <https://essentia.upf.edu/installing.html>
- <https://essentia.upf.edu/reference/std_RhythmExtractor2013.html>
- <https://essentia.upf.edu/reference/std_KeyExtractor.html>
- <https://pypi.org/project/essentia/>

## Local LLM eval

Not run. A5.2 performs deterministic extraction only. Soul synthesis and its
behavioral evaluation belong to A5.3.

## Memory and lifecycle

- Shared memory keys added or used: none. Records remain private Music Studio
  domain artifacts.
- Lifecycle states touched: `complete`, `failed`, `awaiting_input`, `canceled`,
  and `blocked_for_human_review`.
- A successful analysis remains `blocked_for_human_review`; it is not an
  approved synthesis or composition source.

## Risk classification

Moderate. A5.2 retrieves untrusted remote media and executes local decoders, but
constrains provider, identity, duration, bytes, retries, output, wall time,
process group, storage, and retention. Setup remains a separate exact human gate.

## Known weaknesses

- Instrumentation, sections, vocal delivery, lyrical traits, target settings,
  and new lyrics are intentionally empty until A5.3 local Soul synthesis.
- MusicBrainz album/release enrichment is not yet implemented; yt-dlp metadata
  is used when present and otherwise the track remains unresolved.
- yt-dlp needs periodic reviewed version updates as YouTube changes. There is no
  automatic updater.
- `owned`, `licensed`, and `public_domain` remain Operator assertions rather
  than legal findings.

## Human review checklist

- [x] Install the optional tool environment through its exact setup gate.
- [ ] Confirm metadata preview shows the intended single video and rights mode.
- [ ] Run one analysis-only reference and inspect BPM/key/confidence evidence.
- [ ] Confirm no source audio or raw transcript remains under `Soul/music`.
- [ ] Confirm the new profile appears under the correct artist/album grouping.
