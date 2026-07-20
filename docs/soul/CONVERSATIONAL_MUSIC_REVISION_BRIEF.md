# Conversational Music Revision Brief

Status: Operator-approved implementation slice

## Purpose

Carry a reviewed `revise` disposition from Chat into one exact Music Studio
revision candidate without requiring the Operator to reconstruct the same
feedback in the dashboard. Soul may draft the revised bounded generation input;
the Operator must review the complete draft and click the exact action before
audio generation begins.

## Approved scope

- Keep a creative flow active after a recorded music review whose disposition
  is `revise`.
- Treat a subsequent explicit revision request as continuation of that exact
  reviewed candidate, not as a new song request.
- Reuse `MusicRevisionDraftService` to translate the stored human review and
  available machine-heard evidence into a 512-character-compatible Sound and
  Structure block plus dedicated BPM, key, time, and preserved lyrics fields.
- Show the complete proposed revision and rationale in Chat before execution.
- Bind the action to the chat, flow, source candidate, complete revision input,
  and current flow digest.
- Revalidate Music Core and the existing Music Studio revision preview before
  invoking the existing bounded revision execution service.
- Return the new MP3/FLAC candidate to Chat and re-enter the normal human review
  loop.

## Boundaries

This slice does not:

- infer revision approval from model output or a conversational `yes`;
- silently change intended lyrics, rights status, duration, or vocal mode;
- revise a kept or rejected candidate;
- automatically retry, keep, reject, trim, export, bind, render, package, or
  publish the resulting candidate;
- add a service, daemon, watcher, scheduler, queue, or unattended continuation;
- create durable personality memory or a skill-private memory store.

## Lifecycle

```text
review recorded as revise
  -> awaiting explicit revision request
  -> blocked_for_human_review with exact revision action
  -> bounded generation
  -> blocked_for_human_review with new candidate
```

Planning and execution terminate as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. Existing detachable dashboard job
receipts may preserve foreground progress across page navigation; unfinished
work is marked failed on dashboard restart and never silently resumed.

## Acceptance

- A kept candidate does not offer revision generation.
- A reviewed `revise` candidate remains addressable in its originating chat.
- Discussion about revision does not execute it.
- The local model may draft but cannot authorize the exact action.
- Lyrics and the four user-required project decisions remain unchanged.
- A stale or mismatched action fails before Core or generation mutation.
- A successful action creates exactly one linked revision candidate and returns
  an authenticated audio attachment.
- Replaying the same action does not generate another candidate.
- Existing initial generation, review, Core, intent-routing, and Music Studio
  regressions remain green.
