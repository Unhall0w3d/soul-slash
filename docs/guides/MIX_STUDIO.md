# Mix Studio

Mix Studio is Soul/'s bounded continuity surface for arranging already-finished
compositions. It records an exact running order without changing the finished
songs and prepares a portable package for a conventional audio editor or DAW.

## A0 workflow

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

## A0 limitations

Mix Studio A0 does not render the final long-form mix. It does not separate
stems, reconstruct instrument tracks, or create a native FL Studio, Ableton,
Logic, or other proprietary project. It provides verified stereo sources and
precise edit instructions so the operator can perform final assembly without
losing lineage.

It also does not publish, schedule work, run in the background, or alter the
finished source exports.

## Related documents

- [Long-form Mix Studio A0 Brief](../soul/LONG_FORM_MIX_A0_BRIEF.md)
- [Long-form Mix Studio A0 Review](../assessments/LONG_FORM_MIX_A0_REVIEW.md)
- [Music Studio](MUSIC_STUDIO.md)
