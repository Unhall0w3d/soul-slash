# Conversational Creative Workflows

Soul can collaborate on Music Studio and Visual Studio work from Chat without turning every mention of music, images, or skills into an invocation. A workflow begins only from an explicit creative action such as `make`, `create`, `compose`, `generate`, or `render`, or when the Operator is answering a question in an already active creative workflow.

## Music brief

The Operator must supply four decisions. Soul does not silently invent them:

- intent;
- one supported duration: 30, 90, 180, or 600 seconds;
- mode: vocal or instrumental;
- rights status: original, licensed, or public domain.

Soul may draft omitted optional material—title, BPM, key, meter, seed, a single coherent Sound and Structure block no longer than 512 characters, and section-marked lyrics when vocal lyrics were not supplied. Those values remain visible and editable before generation.

## Visual brief

The Operator supplies a clear visual intent. Soul may draft the title, prompt, exclusions, aspect ratio, and seed. Existing kept Music or Visual Studio projects may be referenced by exact title; deterministic code verifies that the title resolves to one reviewed candidate.

## Exact flow

```text
explicit request
→ ask only for missing required decisions
→ show the complete brief
→ exact click-authored generation action
→ revalidate and enter Music Core when required
→ bounded local generation
→ authenticated audio player and/or image in Chat
→ Operator feedback
→ visible exact review action
→ recorded studio review and lineage
```

The generation click is the authorization; the UI does not require retyping its prefilled confirmation phrase. A changed brief or stale digest is rejected. Repeating a completed action is idempotent and does not create duplicate candidates or reviews.

## Present boundary

Candidate creation and review are chat-native. Revision generation, destructive rejection, music/visual binding, full companion rendering, final audio export, upload-package export, and external publication retain their dedicated Studio gates. Soul can preserve the candidate lineage and direct the Operator to the appropriate Studio surface, but it must not claim those later operations occurred from conversation alone.

Creative flow records are private per-conversation task state under ignored runtime storage. They are not durable personality memory, do not run a watcher or resident model, and terminate as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`.

## Conversational routing rule

Mention is not invocation. Statements such as `I am working on your skills`, `we should discuss music later`, or `that image was good` remain ordinary conversation unless they answer an active workflow question. Explicit catalog questions such as `What skills do you have?` still use the read-only catalog.
