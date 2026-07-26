# Invocation Catalog A1 Brief

## Human direction

Expose an invocation list alongside the existing skill inventory so the
Operator can understand what Soul may actually do, when it is appropriate,
which inputs are required, which Core is needed, and where human authority
remains.

Live microphone, wake-word, screen-recognition, and subjective creative
validation are intentionally deferred until the Operator is back at the
computer.

## Candidate scope

- One curated public invocation catalog.
- A read-only service and application operation with bounded category and text
  filters.
- A compact Chat-side Dashboard card and read-only detail dialog.
- Deterministic conversational requests for the whole catalog, one category,
  or one exact invocation.
- Entries describe required inputs, optional inputs, Core requirements,
  approval behavior, result shape, limitations, and example requests.
- Examples are rendered as inert text. Viewing or filtering the catalog cannot
  execute an invocation.
- Registry-backed availability validation for entries associated with
  production skills.

## Explicitly excluded

- Running an invocation from the catalog.
- Automatic Core changes.
- Automatic approval or inherited voice authority.
- A new service, watcher, listener, scheduled task, or polling loop.
- Live microphone, wake-word, notification, screen, model-persona, or media
  quality acceptance.
- Changes to Skill Studio promotion or Self Augmentation authority.

## Lifecycle and authority

Catalog inspection terminates as `complete` or `failed`. It is always
read-only and carries `mutation: none`.

Examples describe possible Operator wording. They are not authorization. Any
subsequent request still enters the owning deterministic router, Core check,
preview, digest, and human gate.
