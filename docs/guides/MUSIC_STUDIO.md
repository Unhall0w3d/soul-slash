# Music Studio

Music Studio is Soul's local composition workspace. It preserves the exact creative brief, generates bounded candidates, records machine and human listening evidence, supports revision lineage, binds reviewed artwork, and exports finished audio or a local YouTube upload package.

Open it from **Creative Studios → Music Studio**.

## Core and resource model

Production music generation uses the **Music Core**: chat moves to the NVIDIA reserve while the ACE-Step Vulkan music runtime uses AMD only for the bounded generation. The music model is loaded on demand and exits afterward. No resident worker or background queue is created.

Use **Inspect resources** before generation. A project may be drafted in another Core, but generation requires the compatible Music Core and an available AMD Vulkan device.

## Create a composition

Required creative decisions are:

- **Intent** — what the piece should communicate or accomplish;
- **Duration** — currently 30, 90, or 180 seconds;
- **Mode** — vocal or instrumental;
- **Rights status** — original, licensed, or public-domain material.

The current form also records title, BPM, key, meter, seed, sound and structure, and—when vocal—lyrics with section markers.

The **Sound and structure** field is limited to 512 characters. Describe one coherent sonic identity: genre, principal instruments, mood, texture, and broad progression. Put BPM, key, meter, and detailed lyric/section order in their dedicated fields. Compatible constraints generally work better than a long list of competing genres and micro-directions.

Instrumental mode uses the runtime's dedicated no-vocal condition. Do not add placeholder lyrics to an instrumental project.

## Generate a candidate

```text
create immutable project brief
→ inspect resources
→ preview exact candidate scope
→ authorize bounded generation
→ job persists independently of the open page
→ validated FLAC master + MP3 proxy
→ human review
```

The preview binds the project input, candidate ID, model profile, resource scope, and digest. Clicking the prefilled approval control authorizes only that candidate.

Once accepted, the generation job continues if you navigate to another dashboard page. Returning to the project follows the durable job record and restores progress or the terminal result. Cancellation is separately scoped to the active candidate.

The runtime may automatically retry a detected collapsed audio-code plan with a derived seed. It stops after the bounded retry limit rather than producing an endless loop.

## Listen and review

Each candidate shows newest first, provides an MP3 player and lossless FLAC, and records generation timing. The human review covers musical quality, prompt adherence, vocal adherence, lyric adherence, a 1–5 rating, notes, and one disposition:

- **Keep** — retain as an accepted candidate and unlock export/trim paths.
- **Revise** — retain the candidate as lineage and prepare a materially changed successor.
- **Reject** — preview and permanently remove the rejected candidate.

Older revised versions collapse but remain inspectable.

## Vocal evidence and revision

Optional CPU transcription compares intended and machine-heard lyrics, formats repeated sections, reports sequence recall and likely problem lines, then exits. “Machine heard OK” routes to human listening; “Machine heard BAD” recommends revision. Neither route approves or rejects music.

**Ask Soul to draft revision** translates recorded evidence into an editable sound/structure block, lyrics, BPM, key, meter, and new seed. Review and edit that packet before previewing a new candidate. A retry uses a new candidate and preserves the source.

## References and artist profiles

The Reference Constellation can inspect a supported song URL after a rights-status declaration. Metadata preview downloads no media. The separate analysis gate may temporarily acquire bounded source audio, derive fallible musical evidence, create a private profile, and remove source audio, analysis WAV, and temporary transcription at every terminal outcome.

Observed evidence is not copied expression. Soul can draft an original composition target from that evidence; the Operator may approve, reject, or retry the entire packet or one component. Two to five approved targets may be fused into one new coherent target.

Deleting a reference permanently removes that profile and empty artist/album groupings while respecting saved fusion dependencies.

## Finishing, visuals, and publication package

A kept candidate can:

- export a lossless FLAC and derived MP3 under `~/Music/soul-music/<song>/`;
- create one source-derived front/back trimmed copy while preserving the original;
- receive an exact reviewed still from [Visual Studio](VISUAL_STUDIO.md);
- render a static 16:9 visual presentation with selected fit, matte, and fades;
- mux the exact candidate audio into a local MP4;
- generate an editable, exact YouTube upload package containing the MP4, thumbnail, description sidecar, and private-upload metadata.

The package operation does not contact YouTube. Upload visibility, final metadata, and publication remain the Operator's responsibility.

## Deletion boundary

Project deletion inventories and permanently removes the private composition, candidates, archive-owned audio, inputs, logs, transcription, and reviews. Finished exports already copied to `~/Music/soul-music` remain untouched.

## Related setup and engineering references

- [`docs/GETTING_STARTED.md`](../GETTING_STARTED.md)
- [`docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md`](../soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md)
- [`docs/soul/MUSIC_YOUTUBE_PACKAGE_BRIEF.md`](../soul/MUSIC_YOUTUBE_PACKAGE_BRIEF.md)
