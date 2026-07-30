# Long-form Mix Studio A0 Brief

## Objective

Add a bounded Mix Studio surface that lets the operator arrange already-finished
Soul music exports into an immutable edit decision list (EDL), inspect the exact
timeline, and export a portable package for a conventional audio editor or DAW.

This slice consolidates the first useful portions of:

- `track_long_form_mix_editor`
- `track_structured_creative_exports`

It does not render a new mixed master.

## Approved A0 scope

The operator may:

1. list eligible, finished Soul music exports;
2. order those sources into a mix plan;
3. assign bounded head/tail trims, crossfades, and transition notes;
4. save the plan as an immutable, digest-addressed record;
5. inspect deterministic cue and duration calculations;
6. preview an exact handoff package;
7. explicitly authorize export of that package beneath
   `~/Music/soul-music/mixes`.

The handoff package must contain copied stereo source masters, checksums, a
machine-readable EDL, a cue sheet, and an honest README describing what the
package is and is not.

## Source eligibility

A source is eligible only when all of the following are true:

- it has a finished-export receipt using the supported schema;
- its project and candidate identifiers are valid;
- its candidate has a recorded `keep` disposition;
- its exported master and supporting metadata exist;
- the current file digests exactly match the export receipt.

Trim receipts and incomplete, rejected, revised, or merely generated candidates
are not eligible.

## Bounds

- Maximum plans: 100.
- Maximum sources in one plan: 100.
- Plan JSON and individual free-text fields are bounded.
- Trim values must remain within the source duration.
- The first item has no incoming crossfade.
- Later crossfades are at most 10 seconds and shorter than both adjacent usable
  source durations.
- No output path may escape the configured private state or export root.
- Symlinks are rejected at protected write boundaries.
- Existing exports are never overwritten.

## Authority and lifecycle

Creating an immutable plan is a local, reversible metadata mutation.

Handoff export uses an exact preview/execute gate:

```text
EXPORT_MIX_HANDOFF
```

Execution must bind to the preview digest and must terminate as `complete`,
`failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`. It may not
continue in the background after returning control.

## Explicit non-goals

A0 does not:

- synthesize or render audio;
- claim to separate stems from a stereo master;
- create a native FL Studio, Ableton, Logic, or other proprietary project;
- alter finished source exports;
- publish externally;
- add a daemon, watcher, schedule, service, or polling loop;
- infer human approval from model output.

## Review acceptance

Candidate-complete A0 must demonstrate:

- deterministic source eligibility and digest rejection;
- exact timeline math for trims and crossfades;
- immutable plan storage and bounded validation;
- non-overwriting, checksum-verified handoff export;
- a dashboard surface that clearly states the stereo-source limitation;
- deterministic tests and a completed human review artifact.
