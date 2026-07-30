# Mix Studio

Mix Studio is Soul/'s bounded continuity surface for arranging already-finished
compositions. It records an exact running order without changing the finished
songs and prepares a portable package for a conventional audio editor or DAW.

## Workflow

1. Open **Creative Studios → Mix Studio**.
2. Choose finished masters from **Eligible sources**.
3. Reorder the sequence and set:
   - the first and last source seconds to retain;
   - an incoming crossfade for every item after the first;
   - a short transition note for the human editor.
4. Add a title and intent.
5. Select **Seal immutable plan**.
6. Inspect the exact calculated timeline.
7. Select **Preview editor handoff**.
8. Review the bound paths, source hashes, cues, and destination.
9. Select **Export exact handoff** to authorize that reviewed digest.
10. Select **Preview listening render** and inspect the exact render scope.
11. Select **Render exact listening candidate** to create the private FLAC/MP3
    review artifacts.
12. Listen in the dashboard and decide whether the plan should be revised or
    considered for a later final export.

Changing a sealed plan means creating another plan. The original remains as
lineage evidence.

## Eligible sources

Mix Studio only offers candidates that:

- were marked `keep`;
- were exported through Music Studio's finished-song flow;
- still contain their required master and metadata files;
- exactly match the hashes in the finished-export receipt.

If a finished source changed outside Soul/, inventory fails closed for review
instead of silently using different audio.

## Timeline semantics

Each item references one finished stereo master and records:

```text
source project and candidate
source master SHA-256
trim start
trim end
incoming crossfade
transition note
calculated timeline start and end
```

The first source starts at zero and cannot have an incoming crossfade. Later
crossfades are limited to 10 seconds and must be shorter than both adjacent
usable source ranges.

## Handoff package

The exact package is written beneath:

```text
~/Music/soul-music/mixes/
```

It contains:

```text
source_*.flac       copied, checksum-verified stereo masters
mix.edl.json        machine-readable immutable edit decision list
cue-sheet.csv       editor-friendly timing and transition rows
README.md           intent, limitations, and reconstruction guidance
checksums.sha256    sha256sum-compatible package checksums
```

## Listening candidates

The A1 listening lane renders the sealed trims and crossfades in the foreground
from the same checksum-verified stereo masters. It writes private, immutable
review artifacts beneath `Soul/private/mix_renders`:

```text
master.flac         lossless 48 kHz stereo listening render
listening.mp3       320 kbps dashboard proxy
render.json         exact plan, render profile, measurements, and hashes
checksums.sha256    output integrity manifest
```

The MP3 is available only through the authenticated Dashboard ranged-media
route. Rendering does not mark the mix accepted and does not create a release
master.

## Limitations

Mix Studio does not separate stems, reconstruct instrument tracks, or create a
native FL Studio, Ableton, Logic, or other proprietary project. The A1 render is
listening evidence, not a mastered or accepted final export.

It also does not publish, schedule work, run in the background, or alter the
finished source exports.

## Related documents

- [Long-form Mix Studio A0 Brief](../soul/LONG_FORM_MIX_A0_BRIEF.md)
- [Long-form Mix Studio A0 Review](../assessments/LONG_FORM_MIX_A0_REVIEW.md)
- [Long-form Mix Studio A1 Listening Render Brief](../soul/LONG_FORM_MIX_A1_LISTENING_RENDER_BRIEF.md)
- [Music Studio](MUSIC_STUDIO.md)
