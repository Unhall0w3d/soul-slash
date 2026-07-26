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

After both candidates are kept and exactly bound, Chat may reuse the existing
static-presentation, full-duration render, finished-song export, and local
upload-package services. Each remains its own digest-bound action and stops for
human review. Image-guided motion, motion review and binding, visual deletion,
and external publication remain outside the conversational workflow.

The later A1 native-motion extension permits a kept or exact existing visual
context to start one 4-, 8-, or 12-second text-to-video candidate through the
existing FastWan preview and execution gate. Chat returns the WebM for review.
A stored `revise` motion review can unlock one linked Chat-prepared native
revision. The prior candidate remains immutable and each render retains its
own Core-aware exact action.

## Core transitions

Creative generation requires Music Core (NVIDIA chat, AMD creative lane). The
server may prepare an exact Core transition as part of a creative action. The
transition runs only after an Operator clicks the server-authored action, and
still delegates to `CoreOrchestrationService`, preserving active-work, lease,
activity-probe, digest, confirmation, allowlist, and timeout checks. No model
may choose or authorize a Core transition. Soul does not silently restore the
previous Core after creative work.

Before presenting an executable creative action, Soul must resolve and expose:

- the active Core;
- the exact Core required by the pending operation;
- whether the approved action includes a Core transition;
- why that Core is required.

Music generation and music revision require Music Core. Visual-only generation
and image-guided visual revision require AMD-Free Core. Resolving reviewed
existing sources, recording reviews, binding lineage, and preparing exports do
not imply a Core transition unless their downstream operation performs bounded
generation.

The Core requirement is deterministic server state included in the reviewed
workflow digest and action metadata. It is not chosen by the local model. A
single Operator click may authorize the exact creative action and its disclosed
Core transition; execution must revalidate the requirement, current Core,
active work, lease, profile, and runtime digest before changing services. If
the Core is already suitable, the same action proceeds without a redundant
transition.

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
- visible active/required Core preflight, already-suitable behavior, Core
  transition blockers, and no-model-authorization evidence;
- music, visual, combined, existing-source, binding, render, and export flow
  tests using bounded fakes;
- dashboard attachment/action rendering checks;
- updated skill catalog, user documentation, and human review artifact.
