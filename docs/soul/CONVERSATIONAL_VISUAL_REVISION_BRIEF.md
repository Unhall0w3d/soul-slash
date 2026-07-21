# Conversational Visual Revision Brief

Status: Operator-approved implementation slice

## Purpose

Carry a Chat-recorded visual `revise` review into one linked Visual Studio
image-guided edit while preserving the source candidate, human review,
Core/resource checks, exact preview, and separate click authority.

## Approved scope

- Keep a reviewed visual `revise` disposition active in its originating chat.
- Require a subsequent explicit revision request; discussion alone does not
  draft or execute an edit.
- Use the configured local chat provider to translate the recorded visual notes
  and source project metadata into one bounded edit instruction, seed, and
  concise rationale.
- Treat project fields and review evidence as untrusted data in the model
  request. The model receives no authority and does not execute tools.
- Display the complete instruction, seed, source identity, and rationale before
  an action is available.
- Bind the action to the chat, flow, source candidate, complete draft, and
  current flow digest.
- Revalidate AMD creative availability and reuse Visual Studio's existing
  `edit_preview` and `edit_execute` services.
- Return the linked image to Chat and re-enter the normal human review loop.

## Boundaries

- The source candidate remains immutable.
- The model does not claim to see pixels; the guided edit model receives the
  reviewed source image only after the exact action click.
- No automatic keep, rejection, deletion, binding, final render, packaging,
  upload, or publication is added.
- No cloud provider, new service, daemon, watcher, scheduler, queue, polling
  loop, durable memory key, or skill-private memory store is introduced.

## Lifecycle

```text
visual review recorded as revise
  -> awaiting explicit revision request
  -> blocked_for_human_review with visible edit draft
  -> exact guided-edit action
  -> blocked_for_human_review with linked visual candidate
```

The task may also terminate as `complete`, `failed`, `awaiting_input`, or
`canceled`.

## Acceptance

- A kept visual does not offer guided revision.
- Casual revision discussion does not call the local model or Visual Studio.
- The draft is local-only, bounded, valid text, and uses a valid seed.
- A stale action fails before Core or visual mutation.
- The existing source candidate ID reaches the authoritative edit preview and
  execution unchanged.
- Successful execution produces exactly one linked candidate and authenticated
  image attachment.
- Replaying the same action produces no duplicate image.
- Music revision/disposition and initial combined workflows remain green.
