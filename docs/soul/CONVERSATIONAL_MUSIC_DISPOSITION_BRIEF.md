# Conversational Music Disposition Brief

Status: Operator-approved implementation slice

## Purpose

Let an originating Chat complete the existing kept-song export or rejected-song
deletion flow without bypassing Music Studio's exact preview, digest,
confirmation, lineage, integrity, and path protections.

## Approved scope

- Keep a newly recorded music `keep` or `reject` review available as bounded
  per-chat task state.
- Require an explicit follow-up request before preparing either operation.
- Reuse `MusicCandidateDispositionService` for the authoritative export or
  rejection preview and execution.
- Show the exact operation, retained/deleted files, destination where relevant,
  and non-overwrite/publication boundaries before execution.
- Bind the Chat action to the current flow and the exact downstream preview.
- On export, report the finished local folder without uploading or publishing.
- On rejection, remove the rejected candidate through the existing tombstoned
  Music Studio operation and remove its player from the active flow.

## Boundaries

- Recording `keep` does not automatically export.
- Recording `reject` does not automatically delete.
- A conversational `yes`, model output, or review disposition is not execution
  authorization; the exact action click is required.
- No overwrite, export deletion, project deletion, trim, revision, binding,
  rendering, packaging, upload, or publication behavior is added.
- No service, daemon, watcher, scheduler, polling loop, or post-return process is
  introduced.

## Lifecycle

```text
recorded keep review
  -> explicit export request
  -> exact export preview/action
  -> complete local finished-song export

recorded reject review
  -> explicit deletion request
  -> exact rejected-candidate preview/action
  -> complete tombstoned deletion
```

The bounded task may also terminate as `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`.

## Acceptance

- Mentioning export or deletion does not prepare an action.
- A kept candidate can prepare export but not rejection.
- A rejected candidate can prepare rejection but not export.
- The visible action contains the authoritative downstream preview scope.
- Stale flow or downstream state fails before mutation.
- Exact export is idempotent and never overwrites an existing destination.
- Exact rejection creates the existing receipt and removes only the reviewed
  candidate-owned material.
- A new explicit creative request may close an unconsumed disposition flow and
  begin a new brief rather than becoming trapped in the old flow.
