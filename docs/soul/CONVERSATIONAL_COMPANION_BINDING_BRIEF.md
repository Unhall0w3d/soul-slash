# Conversational Companion Binding Brief

Status: Operator-approved implementation slice

## Purpose

Allow an originating Chat creative flow to bind one exact reviewed Visual
Studio still to one exact reviewed Music Studio candidate by reusing the
existing Visual Studio promotion and Music visual-companion gates.

## Approved scope

- Support combined flows containing newly generated candidates, exact existing
  kept candidates, or one of each.
- Require every newly generated source to have a recorded `keep` review.
  Existing sources already pass the current exact-title kept-candidate lookup.
- Require a separate explicit binding request; review or discussion alone does
  not prepare or execute a binding.
- Preview the binding through `VisualStudioService#promotion_preview` and show
  the exact music project/candidate, visual project/candidate, resulting visual
  identity, and external-publication boundary.
- Bind an outer Chat action digest to the originating chat, flow, both source
  identities, and the authoritative downstream preview.
- On click, pass the unchanged downstream confirmation and digest to
  `VisualStudioService#promotion_execute`.
- Preserve the bound companion record as active Chat task context for a later,
  separately reviewed static-presentation slice.

## Boundaries

- `revise`, `reject`, or unreviewed candidates cannot bind from Chat.
- Binding copies the exact reviewed image into the exact music candidate's
  visual lineage. It does not mutate either source candidate.
- No loop/static-presentation encoding, full companion render, final review,
  trim, music export, publication-package creation, upload, or publication is
  included.
- No model chooses candidate identities or grants approval.
- No cloud provider, service, daemon, watcher, scheduler, queue, polling loop,
  memory key, or skill-private memory store is introduced.

## Lifecycle

```text
combined candidates resolved and kept
  -> explicit bind request
  -> blocked_for_human_review with exact binding preview
  -> exact binding action
  -> blocked_for_human_review at base_bound
```

The task may also terminate as `complete`, `failed`, `awaiting_input`,
`canceled`, or be superseded by an explicit new creative request.

## Acceptance

- Discussion does not prepare or execute a binding.
- An unreviewed, revised, or rejected new candidate cannot bind.
- A stale outer action mutates nothing.
- Source project and candidate IDs reach the authoritative promotion preview
  and execution unchanged.
- One successful click creates one bound companion record and no render.
- Replaying the action creates no duplicate binding.
- Initial generation, review, revision, music dispositions, and Studio-native
  companion behavior remain green.
