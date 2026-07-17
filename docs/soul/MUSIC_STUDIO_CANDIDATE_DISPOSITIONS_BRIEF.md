# Music Studio candidate dispositions brief

## Approved intent

Turn the recorded human listening disposition into an explicit next action:

- `revise`: preserve the candidate as an older playable version once a linked
  revision exists.
- `reject`: permanently remove that candidate's audio, input, and transcription.
- `keep`: export the exact reviewed candidate into the Operator's finished local
  music library.

Recording a review does not silently perform a destructive or external-library
mutation. Reject and keep each require a fresh preview, state digest, and exact
confirmation.

## Revision history presentation

A candidate marked `revise` remains fully available while its replacement is
being drafted or generated. Once a candidate whose `source_candidate_id` points
to it exists, the older card collapses to its identity and music player. The
Operator may expand it to inspect evidence, review history, and controls.

No candidate is called an older version merely because it sorts earlier; the
label is based on explicit lineage.

## Rejection deletion

`DELETE_REJECTED_CANDIDATE` is required after an exact preview. Execution
revalidates the current `reject` review, candidate input digest, actual FLAC and
MP3 digests, and linked descendants.

Deletion removes the candidate directory, including FLAC, MP3, exact generation
input, logs, and transcription evidence, plus its current review. A small private
rejection receipt remains under project review state containing identity,
digests, the rejected review, and descendant IDs. Prior immutable review-history
revisions remain. This preserves lineage without retaining rejected media.

If the candidate has already been exported to the finished library, rejection
stops. Removing a finished export requires a separately reviewed operation.

## Finished-song export

`EXPORT_FINISHED_SONG` is required after an exact preview. The default library
is `~/Music/soul-music/<sanitized-song-title>/`.

The export is assembled in an owner-private staging directory and atomically
renamed into place. It never overwrites an existing folder. A successful export
contains:

- `master.flac`
- `listening.mp3`
- `song.json`
- `song-info.md`
- `lyrics.txt` for vocal songs only

Metadata uses the selected candidate's exact input, so revised BPM, key, time,
seed, Sound and Structure, and intended lyrics are not replaced by original
project defaults. `song-info.md` includes Title, Intent, Duration, Mode, Rights
Status, BPM, Key, Time, Seed, Sound and Structure, and intended lyrics/markers.

Vocal export requires completed candidate transcription and writes the formatted
machine-heard lyric sheet to `lyrics.txt`. Instrumental export requires no
transcription and does not invent a lyric file.

The copy is digest-verified, private (`0700` directory, `0600` files), local
only, and idempotent for the same exact candidate. It performs no upload or
external publication.

## Lifecycle and boundaries

- Missing/mismatched review or missing vocal transcription: `awaiting_input`.
- Preview: `blocked_for_human_review`.
- Stale state, path integrity issue, destination collision, or wrong phrase:
  `blocked_for_human_review`.
- Confirmed deletion/export: `complete`.

There is no service, queue, watcher, scheduled task, retry loop, automatic
disposition, background continuation, or YouTube integration in this slice.
