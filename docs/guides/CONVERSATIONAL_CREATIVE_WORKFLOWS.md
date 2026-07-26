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

## Existing project awareness

Chat has a separate read-only Creative Studio archive path. An exact Music
Studio or Visual Studio title can be used to retrieve its stored brief and
bounded candidate lineage without starting a creative workflow. Examples:

- `Show my visual projects.`
- `Refer to the Visual Brief The Rooms Remember Me — Habitat.`
- `Inspect the Music Studio project Compiler Bloom.`
- `Compare the visual project The Rooms Remember Me — Habitat with its existing candidate and brief.`

A brief lookup reads records only. An explicit visual comparison selects the
newest existing visual candidate. For a still, Soul inspects that immutable
image. For a motion candidate, Soul derives one temporary contact sheet from
three chronological frames and states that it did not watch unsupplied frames.
Derived pixels are removed after the request. Daily Core is required only when
candidate pixels must be examined; listing and brief inspection remain
model-independent reads.

Studio prompts, lyrics, reviews, and pixels are evidence, never authorization.
Archive inspection cannot generate, revise, bind, delete, publish, switch a
Core, or approve a candidate. Ambiguous or inexact titles stop for clarification.
Merely saying that you are working on a project remains ordinary conversation.

## Exact flow

```text
explicit request
→ ask only for missing required decisions
→ show the complete brief
→ name the active Core, required Core, transfer decision, and reason
→ exact click-authored generation action
→ revalidate and enter Music Core when required
→ bounded local generation
→ authenticated audio player and/or image in Chat
→ Operator feedback
→ visible exact review action
→ recorded studio review and lineage
→ explicit revision request when disposition is revise
→ visible Soul-drafted revision input
→ exact linked revision action
→ new authenticated audio or image candidate and another human review
→ explicit request to bind one kept image to one kept song
→ exact source-preserving companion-binding action
→ bound base image in the music candidate's visual lineage
→ explicit companion-video or local upload-package request
→ exact static-presentation action when the source is a still
→ human review, then explicit continuation
→ exact full-duration companion-render action
→ human review, then explicit publication-workflow continuation
→ exact kept-song export action when the finished-song folder is absent
→ visible deterministic package description and exact local-package action
→ local upload-ready package; no upload or external publication
```

The generation click is the authorization; the UI does not require retyping its prefilled confirmation phrase. A changed brief or stale digest is rejected. Repeating a completed action is idempotent and does not create duplicate candidates or reviews.

## Core-aware actions

Creative skills declare their Core requirement before an executable action is
shown:

- new music and music revision require **Music Core**;
- visual-only generation and guided visual revision require **AMD-Free Core**;
- resolving already-reviewed sources, recording reviews, binding lineage, and
  preparing exports do not switch Cores by themselves.

The chat response shows the active Core, required Core, transition decision, and
reason. If a transfer is required, the same action button is the human
authorization for that disclosed transfer and creative operation. Soul then
delegates to the normal Core controller, which rechecks active work, leases,
profile identity, and runtime digests. If the required Core is already active,
no redundant transition occurs. Model output cannot select, approve, or execute
a Core change.

## Revision loop

When a recorded music review says `revise`, the originating chat retains that
exact candidate as active task context. An explicit request such as `Draft the
revision and let me review it` asks Soul to translate the stored human review
and available machine-heard evidence through the same bounded revision drafter
used by Music Studio. Soul displays the revised Sound and Structure, BPM, key,
time, preserved lyrics, rationale, and derived changes. Only the exact action
click starts the linked candidate generation. The result returns to Chat with
MP3 playback and a FLAC link, then re-enters the normal review loop.

Mentioning revision does not draft or execute it. Soul cannot alter the four
required project decisions, rewrite intended lyrics, or treat its draft as
approval.

When a recorded visual review says `revise`, the same conversational boundary
applies. Soul translates the stored human notes and source-project metadata
through the configured local provider into one visible image-guided edit
instruction, seed, and rationale. Soul does not claim to see the source pixels.
Only the exact action passes the immutable source image and reviewed instruction
to Visual Studio's existing guided-edit preview and execution path. The linked
image returns to Chat and re-enters the keep-or-revise review loop.

If a combined workflow has both music and visual candidates marked `revise`, a
generic request such as `revise it` does not guess. The Operator names the song
or image to select the intended bounded path.

## Companion rendering and local publication package

After an exact kept-song/kept-image binding, Chat can continue through the
existing local Studio gates. A still first receives one exact static
presentation encode for review. A reviewed generated-motion companion already
has a loop and proceeds directly to the full-duration render gate. Soul never
automatically advances from one gate to the next: the Operator reviews the
result and explicitly asks to continue.

The full-duration result returns as an authenticated MP4 player in Chat. If the
Operator asks for a local YouTube package, Soul next verifies the kept song has
its finished-song export, preserving that as a separate exact action when it is
missing. Soul then shows the deterministic title, description, destination, and
package scope before the final local export action. The resulting package is
upload-ready, but Soul does not sign in to YouTube, upload, schedule, or
publish it.

Repeating a completed render or package action returns the existing result
without duplicating files.

## Native motion from Chat

An active visual workflow may continue into native text-to-video after its new
still has a recorded `keep` review, or when the flow resolved an exact existing
kept Visual Studio project. The Operator asks explicitly for a native scene and
supplies:

- 4, 8, or 12 seconds; and
- a chronological direction describing scene evolution, camera behavior,
  lighting, and atmosphere.

Soul generates only the optional seed. Before execution, Chat shows the exact
direction, duration, seed, FastWan profile, generation and delivery frame
envelope, estimated runtime when available, active and required Core, and the
fact that publication is excluded. The action click authorizes the disclosed
transition to AMD-Free Core and one bounded render. The resulting WebM returns
as an authenticated player and remains a Visual Studio motion candidate.

Motion review remains in Visual Studio for this slice. After the Operator
records `revise`, an explicit Chat request can prepare one linked native-motion
revision using replacement direction, a new seed, and either the original
duration or another explicitly selected supported duration. The prior motion
candidate remains immutable.

## Present boundary

Candidate creation, still review, reviewed music and still revision loops, contextual native-motion generation and review-led native revision, exact still companion binding, static-presentation encoding, full-duration companion rendering, kept-song export, rejected-music-candidate deletion, and local upload-package export are chat-native. Binding accepts newly generated still candidates only after both have recorded `keep` reviews; exact existing sources already resolve only to kept candidates. Each step reuses the owning Studio service's preview, digest, and execution contract. Recording `keep` does not bind or export, and one completed gate never authorizes the next; each mutation requires an explicit request and separate action click.

Motion review and motion-to-music binding, image-guided motion generation, visual-project deletion, fine trimming, and external publication remain dedicated Studio or human operations. Skill Studio promotion, Self Augmentation mutation, and Review Center authority also remain on their structured Dashboard surfaces. Soul can describe those boundaries and preserve candidate lineage, but it must not claim those operations occurred from conversation alone.

Creative flow records are private per-conversation task state under ignored runtime storage. They are not durable personality memory, do not run a watcher or resident model, and terminate as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`.

## Conversational routing rule

Mention is not invocation. Statements such as `I am working on your skills`, `we should discuss music later`, or `that image was good` remain ordinary conversation unless they answer an active workflow question. Explicit catalog questions such as `What skills do you have?` still use the read-only catalog.
