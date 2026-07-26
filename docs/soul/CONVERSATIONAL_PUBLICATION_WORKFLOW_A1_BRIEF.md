# Conversational Publication Workflow A1 Brief

Status: Operator-authorized implementation slice

## Purpose

Continue an existing reviewed music-and-visual Chat workflow from exact lineage
binding through local video rendering and a local YouTube upload package. Chat
must reuse the same Music Studio gates as the Dashboard and must not invent,
approve, upload, or publish anything.

## Approved flow

```text
reviewed song + reviewed visual
-> exact lineage binding
-> exact static-presentation encoding when required
-> exact full-duration companion render
-> exact finished-song export when required
-> exact local YouTube package export
```

Generated-motion companions already contain their reviewed loop and therefore
skip only the static-presentation encoding step.

## Conversational behavior

- A discussion of video, export, or publication is not an invocation.
- An explicit request to create the companion video prepares the next exact
  gate required by the bound visual record.
- An explicit upload-package request prepares unmet local prerequisites in
  order; it never treats the request as authority for later gates.
- Each completed step returns its local artifact to Chat when one exists and
  explains the next explicit request.
- The package description is drafted by the existing deterministic publication
  service and shown in full before its exact export action.

## Authority and lifecycle

Every action card is server-authored and digest-bound. The click authorizes only
that exact local step. Model output cannot authorize any operation.

Each invocation terminates as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. No queue, watcher, daemon, scheduler,
polling loop, upload, publication, or unattended continuation is added.

## Acceptance

- Static and generated-motion lineages select the correct next render gate.
- Stale action digests mutate nothing.
- Full-duration MP4 is returned as an authenticated Chat video attachment.
- Finished-song export remains a separate exact action and keeps a bound flow
  resumable for packaging.
- Package description and exact scope are visible before export.
- Package completion returns a local destination and explicitly reports that no
  upload or publication occurred.
- Existing music-only export, creative review, Core, Studio, and dashboard
  workflows remain unchanged.
