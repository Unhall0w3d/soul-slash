# Music Studio A3 vocal-analysis brief

## Approved intent

Add an optional, explicit post-generation pass that transcribes a vocal candidate and compares the machine-heard sequence with the project lyrics. The evidence helps the Operator decide where to listen and whether a revision attempt is warranted.

## Authority and routing

- `Machine heard OK` routes to a human listening test.
- `Machine heard BAD` routes to an Operator-triggered revision attempt.
- Neither result approves, rejects, promotes, regenerates, or rewrites a candidate.
- Only the existing human listening review records acceptance evidence.

## Execution boundary

The pass begins only after the Operator previews its exact candidate, audio digest, lyric digest, CPU lane, model, thread count, and timeout, then types `ANALYZE_MUSIC_CANDIDATE`.

It runs whisper.cpp as one foreground process group with CPU-only inference, at most eight threads, a 360-second timeout, bounded logs, and no retry. Completion, failure, timeout, signal, or abandoned stream terminates the owned process group. The model is not a service and is not resident after the command exits.

There is no watcher, daemon, queue, scheduler, listener, automatic analysis, automatic revision, or automatic generation.

## Evidence

Candidate-local evidence records the pinned runtime identity, transcript segments and timestamps, intended and machine-heard lyrics, ordered token recall, per-line heuristic status, route, and an explicit fallibility warning. Re-analysis preserves the prior packet by digest.

The transcript is an ASR estimate over sung vocals. It may miss, merge, or substitute words and must not be treated as ground truth.

For a BAD route, the dashboard exposes the separately bounded revision pipeline
defined in `MUSIC_STUDIO_REVISION_PIPELINE_BRIEF.md`. Soul may draft a material
change from the evidence, but the Operator edits and confirms the exact revision
before any same-project candidate generation begins.
