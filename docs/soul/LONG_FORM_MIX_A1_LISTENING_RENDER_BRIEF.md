# Long-form Mix Studio A1 Listening Render Brief

## Objective

Extend Mix Studio with one bounded, foreground listening render so the Operator
can hear a sealed immutable EDL before deciding whether it deserves a final
export.

The listening render is review evidence. It is not a published master, an editor
project, or evidence of human acceptance.

## Approved A1 scope

For one existing immutable mix plan, the Operator may:

1. preview the exact render scope;
2. authorize that exact digest with `RENDER_MIX_LISTENING_CANDIDATE`;
3. render the plan synchronously from checksum-verified finished stereo masters;
4. receive a lossless FLAC, a 320 kbps MP3, a bounded receipt, and checksums;
5. listen to the MP3 through an authenticated ranged-media dashboard route.

The source exports, immutable plan, and A0 editor handoff remain unchanged.

## Render semantics

- Every source is trimmed to the bounds stored in the sealed EDL.
- A zero-second transition is a deterministic concatenation.
- A positive transition uses the stored duration and a linear equal-time
  crossfade.
- Inputs are rendered to 48 kHz stereo.
- A transparent final peak limiter prevents transition clipping without
  performing loudness normalization or creative mastering.
- The listening MP3 is derived from the rendered FLAC.
- The receipt records the exact command contract, source hashes, plan digest,
  output properties, output hashes, and completion time.

## Bounds

- Maximum rendered duration: 3,600 seconds.
- Maximum source count and crossfade remain bounded by A0.
- FFmpeg and FFprobe are discovered from the local executable path.
- Each command has an explicit timeout and bounded captured output.
- Rendering is foreground-only and terminates before control returns.
- Output is staged atomically beneath `Soul/private/mix_renders`.
- Existing artifacts are never overwritten.
- Protected path components and artifact files may not be symlinks.

## Authority and lifecycle

Preview is read-only and returns an exact digest. Execution requires:

```text
RENDER_MIX_LISTENING_CANDIDATE
```

Execution binds the confirmation to the immutable plan, current source hashes,
render profile, destination, and expected outputs. Source drift or changed
scope blocks execution for human review.

The operation terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`.

## Explicit non-goals

A1 does not:

- mark the mix accepted;
- render or export a release master;
- normalize loudness to a distribution target;
- change transition timing automatically;
- separate stems or modify source masters;
- create a native DAW project;
- publish externally;
- add a daemon, watcher, queue, schedule, service, or background loop.

## Review acceptance

Candidate-complete A1 must demonstrate:

- exact preview/execute digest binding;
- deterministic FFmpeg graph construction for trim, concatenation, and
  crossfade cases;
- bounded foreground execution and failure behavior;
- atomic, non-overwriting, checksum-verified artifacts;
- measured output duration, stereo layout, and sample rate;
- authenticated ranged playback in Mix Studio;
- a visible statement that the candidate is review evidence, not a final
  export;
- deterministic tests and a completed human review artifact.
