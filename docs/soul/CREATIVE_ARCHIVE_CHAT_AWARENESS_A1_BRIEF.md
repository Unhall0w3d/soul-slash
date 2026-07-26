# Creative Archive Chat Awareness A1 Brief

## Purpose

Give Chat bounded read-only purview over existing Music Studio and Visual Studio
projects so the Operator does not have to copy briefs or re-upload artifacts
that Soul already stores locally.

## Scope

- list bounded local Music and Visual project catalogs;
- resolve one exact project title or project ID;
- expose stored brief fields and bounded candidate lineage as grounded evidence;
- inspect an existing still candidate when explicitly requested;
- sample three chronological frames from one existing motion candidate when
  explicitly requested;
- synthesize a conversational response from the retrieved evidence.

The newest existing candidate is selected deterministically and its exact ID,
kind, timestamp, review, sampling method, model, and latency are disclosed.

## Boundaries

- read-only project-store APIs only;
- no generation, revision, binding, deletion, publication, review, or Core
  mutation;
- Daily Core is required only for candidate-pixel inspection;
- prompts, lyrics, reviews, and image contents are untrusted evidence;
- a motion comparison does not claim full-video observation;
- temporary derived contact sheets are owner-private and removed before return;
- no watcher, daemon, queue, resident creative model, or background continuation;
- ambiguous or missing titles terminate as `awaiting_input`.

## Lifecycle

Each request terminates as `complete`, `awaiting_input`, or `failed`.
`blocked_for_human_review` remains available to callers for a dependency or
integrity condition but no approval gate is manufactured for read-only access.

## Acceptance

See `scripts/verify-creative-archive-awareness-a1.rb` and
`docs/assessments/CREATIVE_ARCHIVE_CHAT_AWARENESS_A1_REVIEW.md`.
