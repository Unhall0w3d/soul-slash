# Conversational Creative Studio Brief

Status: owner-authorized implementation candidate

Authorization date: 2026-07-19

## Objective

Expose the reviewed Music Studio, Visual Studio, static visual-companion, and
publication-package workflows through ordinary Soul chat without weakening the
dashboard gates. Soul may gather a creative brief, draft omitted optional
fields, resolve reviewed local candidates, and advance the bounded workflow.
Model output is never authorization. Exact server-authored action cards and an
Operator click remain the authority for Core transitions, generation, binding,
rendering, export, and publication-package creation.

## Conversational boundary

- A mention is not an invocation. Discussion of music, images, skills, or the
  dashboard remains ordinary conversation unless the user expresses an action
  request or continues an active creative workflow.
- Music requires user-supplied intent, exact supported duration, vocal mode,
  and rights status. Soul must not invent those four decisions.
- Soul may draft title, BPM, key, meter, seed, Sound and Structure, lyrics,
  visual prompt, exclusions, framing, and visual seed when omitted.
- Every generated optional field remains visible and editable before the first
  execution action.
- One active creative workflow may be retained per chat. It is task state, not
  durable personal memory, and has explicit complete, failed,
  awaiting_input, canceled, and blocked_for_human_review outcomes.

## Supported paths

```text
new song
new image
new song + new image
new song + reviewed existing image
new image + reviewed existing song
reviewed existing song + reviewed existing image
song/image binding -> static companion -> local upload package
```

The first execution stage creates immutable studio projects and bounded
candidates. Human music and visual review remains authoritative before export,
binding, final rendering, or publication packaging.

## Core transitions

Creative generation requires Music Core (NVIDIA chat, AMD creative lane). The
server may prepare an exact Core transition as part of a creative action. The
transition runs only after an Operator clicks the server-authored action, and
still delegates to `CoreOrchestrationService`, preserving active-work, lease,
activity-probe, digest, confirmation, allowlist, and timeout checks. No model
may choose or authorize a Core transition. Soul does not silently restore the
previous Core after creative work.

## Presentation

Chat messages may carry authenticated local attachments:

- MP3 player plus FLAC link for a music candidate;
- rendered PNG for a visual candidate;
- MP4 player and package paths after the corresponding reviewed gates.

Attachments are structured message metadata, not model-authored HTML or
Markdown. The dashboard renders only known same-origin artifact routes.

## Bounded execution

- Generation uses the existing bounded runtime services and resource lane.
- Detachable dashboard jobs retain progress and terminal receipts; no queue,
  daemon, watcher, scheduler, or new listener is introduced.
- At most one creative execution job is active in the dashboard process.
- A dashboard restart marks an unfinished receipt failed; it never silently
  resumes inference.
- Partial artifacts retain the cleanup guarantees of their owning service.

## Completion evidence

- deterministic routing tests for invocation versus ordinary mention;
- required-field and optional-draft validation;
- exact action digest, stale-action, and idempotent replay tests;
- Core transition blockers and no-model-authorization evidence;
- music, visual, combined, existing-source, binding, render, and export flow
  tests using bounded fakes;
- dashboard attachment/action rendering checks;
- updated skill catalog, user documentation, and human review artifact.
