# Long-form Mix Studio A2 Accepted Export Brief

## Objective

Add the human listening gate and one exact accepted-audio export to Mix Studio.
The Operator reviews an existing A1 listening candidate, records `keep`,
`revise`, or `reject`, and may export only the latest exact `keep` review.

## Approved scope

For one immutable mix plan with a checksum-valid A1 listening render:

1. record sequencing quality, transition quality, an overall rating,
   disposition, and bounded notes;
2. preserve earlier reviews when a review is corrected;
3. preview one accepted export bound to the latest review, plan, render scope,
   and FLAC/MP3 hashes;
4. authorize that exact preview with `EXPORT_ACCEPTED_MIX`;
5. copy the verified FLAC and MP3 into a non-overwriting package under
   `~/Music/soul-music/mixes/finished`;
6. write exact JSON metadata, a human-readable summary, and checksums.

## Authority and lifecycle

Submitting the visible review form is the human review action. Export remains a
separate digest-bound gate. A review other than `keep`, a changed review, source
drift, missing evidence, or a mismatched digest blocks export.

Every operation terminates as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`.

## Preservation

- Mix plans and A1 renders remain immutable.
- Review correction appends prior review evidence to history.
- Existing accepted exports are never overwritten or removed.
- A later corrected `keep` review receives a distinct review-bound package.

## Explicit non-goals

A2 does not:

- master or loudness-normalize audio;
- change trims, order, transitions, or titles;
- sequence or render visual loops;
- publish or upload;
- create a background worker, daemon, queue, or schedule;
- treat deterministic checks as human acceptance.

## Acceptance

- deterministic validation covers review history, non-keep rejection, exact
  digest binding, render drift, idempotency, path protection, and package
  checksums;
- the Dashboard exposes the review and exact-export gates beside the A1 player;
- documentation and tracker records distinguish accepted audio from later
  visual assembly and release mastering;
- the Operator remains responsible for listening and disposition.
