# Music Studio revision pipeline brief

## Approved intent

Turn recorded human listening feedback and optional machine-heard lyric evidence
into a materially revised candidate in the same Music Studio project. Soul may
draft the revision, but the Operator remains the authority over both the exact
creative input and whether generation begins.

## Revision sequence

1. A human review marked `revise`, or a machine route of
   `revision_recommended`, exposes the revision action.
2. The Operator asks Soul to draft a revision.
3. Soul makes one bounded request to a configured local conversation model. It
   receives the exact source Sound and Structure input, recorded human review,
   and bounded machine-heard evidence.
4. Soul returns strict JSON containing a complete revised Sound and Structure
   block, BPM, key, time signature, rationale, and a change list. Code preserves
   the exact intended lyrics; the Operator may deliberately edit them afterward.
5. The draft is shown as editable input. No project, candidate, or audio is
   created by drafting.
6. Preview binds the exact edited revision, source candidate, new candidate ID,
   model profile, resource lane, and artifact plan to a digest.
7. Only `START_MUSIC_REVISION` with the matching digest starts the existing
   bounded foreground music generator.
8. Completion publishes a new candidate linked to its source while preserving
   the source candidate and all prior listening evidence.

## Material-change rule

A revision must change at least one of Sound and Structure, lyrics, BPM, key, or
time signature. Changing only the random seed is a retry, not a revision, and is
rejected below the dashboard boundary.

Soul is instructed to preserve successful choices and address concrete feedback
such as missing opening lines, lyric drift, vocal separation, timing, dynamics,
instrumentation, or section structure. Its draft is advice, not evidence that a
change will work.

When the single model response is unchanged or exceeds the 512-character limit,
and the bounded human or machine evidence specifically shows that the final
intended lyric is incomplete, code may replace the response with one
deterministic closing-measure adjustment. It preserves the source lyrics,
changes only Sound and Structure, remains editable, and does not start audio.
There is no second model request or automatic generation attempt.

## Execution and privacy boundary

- Drafting uses only a configured `local_only` or `local_network` provider.
- The evidence packet is capped at 64 KiB.
- Drafting is one request with a 90-second timeout and no tools.
- Generation keeps the existing single NVIDIA music lease, process-group
  cancellation, bounded logs, offline checkpoints, and duration-derived timeout.
- The AMD conversation model remains available while the NVIDIA music lane runs.
- There is no retry loop, queue, watcher, scheduler, daemon, automatic
  continuation, automatic approval, or external publication.
- If the local model is unavailable, returns invalid JSON, or proposes no
  material change, the workflow stops without generation.

## Lifecycle

- Missing evidence or invalid revision input: `awaiting_input`.
- Provider, integrity, or execution failure: `failed` or
  `blocked_for_human_review`, as appropriate.
- Explicit cancellation: `canceled`.
- Successful draft, preview, and generated candidate:
  `blocked_for_human_review` until the Operator reviews the result.

This slice does not implement rejection cleanup, final export, publication, or
chat-invoked Music Studio skills.
