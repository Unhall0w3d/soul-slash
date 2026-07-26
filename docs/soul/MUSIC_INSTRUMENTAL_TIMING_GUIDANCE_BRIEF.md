# Music Instrumental Timing Guidance Brief

## Status

Approved implementation slice.

## Problem

Music Studio rejects exact second-based movement changes in Sound and
Structure with an instruction to move them into the lyrics script. The same
form then deliberately discards the lyrics script for instrumental projects.
That contradiction prevents an operator from asking an instrumental candidate
to change arrangement on a bounded schedule.

## Runtime constraint

The pinned `acestep.cpp` runtime has no independent instrumental boolean. Its
lyrics input is authoritative:

- exact `[Instrumental]` selects the trained no-vocal condition;
- empty lyrics asks the model to draft lyrics;
- any other text is user-provided lyrical conditioning.

Soul must continue storing an empty human lyrics field for instrumental
projects and sending exact `[Instrumental]` at generation time. Instrumental
section markers must not be passed through the lyrics channel.

## Approved correction

- Keep BPM, key, and meter in their dedicated fields for every project.
- Continue rejecting second-based section schedules in Sound and Structure for
  vocal projects; vocal timing belongs in their lyrics and section markers.
- Allow concise second-based movement guidance in Sound and Structure for
  instrumental projects.
- Teach this distinction directly in Music Studio.
- Disable the lyrics editor while creating an instrumental project so input is
  not silently discarded.
- Preserve the existing exact generation preview, click approval, trained
  no-vocal token, resource lease, timeout, and human listening review.

## Boundaries

- No new generation fields or schema migration.
- No arbitrary instrumental text is sent through the runtime lyrics input.
- No automatic project revision or regeneration.
- No service, watcher, queue, scheduler, or background loop.
- Existing immutable projects and candidates are not rewritten.

## Lifecycle

- Valid project creation: `complete`.
- Invalid vocal caption timing or instrumental lyric content:
  `awaiting_input`.
- Generation remains `blocked_for_human_review` until the existing exact click
  gate is approved.
- Generation failure remains `failed`.

## Verification

- A timed instrumental caption creates successfully.
- Its runtime input still contains exact `[Instrumental]`.
- The same timed caption remains invalid for a vocal project.
- Instrumental lyrics or section markers remain invalid at the service
  boundary.
- The dashboard explains both paths and disables the instrumental lyrics
  editor.
