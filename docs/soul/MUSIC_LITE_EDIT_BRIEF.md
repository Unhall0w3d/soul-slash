# Music Lite Edit brief

## Approved intent

Allow the Operator to clean the beginning or end of an accepted music candidate
without regenerating or altering the source. The first slice supports start/end
trimming only and remains available after the original finished song is exported.

## Source and output contract

- Every edit reads the immutable candidate `master.flac` directly. An edit can
  never use another edit as its source.
- The original candidate, listening evidence, analysis, and finished export are
  never overwritten or deleted.
- Applying a trim creates a new lossless FLAC, a smaller MP3 listening copy, and
  a digest-bound edit receipt under the finished song's `edits/` directory.
- The original candidate must have a recorded `keep` review and a verified
  finished-song export before a trim may be applied.
- More advanced manipulation, including internal cuts, splices, fades, timing
  changes, or arrangement repair, remains outside Soul.

## Review and execution

The dashboard renders the source waveform locally in the browser and lets the
Operator select start and end boundaries. Preview binds the exact candidate,
source artifact digest, start/end times, resulting duration, and destination to
one digest. Clicking the pre-filled `APPLY_MUSIC_TRIM` gate authorizes only that
exact derivative.

The operation invokes bounded foreground FFmpeg commands and terminates as
`complete`, `failed`, `awaiting_input`, or `blocked_for_human_review`. There is
no queue, service, watcher, retry loop, background continuation, model use, or
automatic edit.

## Known boundary demonstrated by current evidence

Weather in the Wiring contains a tail-cleanup issue suitable for this editor.
Teeth of the Signal omits its bridge and transitions directly from its final
hook into the outro; those are internal composition issues and must remain in
the revision workflow. Lite Edit must not imply otherwise.
