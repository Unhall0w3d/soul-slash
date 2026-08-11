# Visual Studio

Visual Studio is Soul's private local image and short-scene workshop. It records a visual brief, generates immutable still or motion candidates through bounded Vulkan lanes, supports guided revisions and review, and can bind one exact accepted visual to one Music Studio candidate.

Open it from **Creative Studios → Visual Studio**.

## Current production boundary

The supported still lane uses the reviewed FLUX.2 Klein Vulkan profile. Image-guided motion uses Wan 2.2; native text-to-video uses the distilled FastWan 2.2 profile. The candidate Blender Scene lane uses pinned Blender 5.2 LTS and EEVEE to construct editable procedural scenes. Each model or renderer runs for one bounded foreground operation. There is no resident image server, Blender daemon, automatic publication, or silent promotion into Music Studio.

Both motion paths currently produce a short 832×480 study. Native text-to-video offers four-, eight-, and twelve-second studies at 24 fps. Runtime varies with the chosen duration and decoder placement; the 1,050-second hard timeout is authoritative. After review and binding, Music Studio repeats the exact accepted clip to the song duration and muxes it with the exact audio. Soul does not represent this as several minutes of unique generated footage.

## Create a visual project

Record:

- **Title** — the archive label;
- **Intent** — what the image should communicate and where it will be used;
- **Frame** — landscape 16:9, square 1:1, or portrait 9:16;
- **Seed** — the reproducibility input;
- **Scene and aesthetic** — subject, environment, composition, lighting, mood, palette, and material language;
- **Exclude** — unwanted text, watermarks, defects, styles, or elements.

Use **Inspect resources** to verify the Core, accelerator, and exact model set before generation.

## Intended flow

```text
visual brief
→ resource inspection
→ exact generation preview
→ one bounded local render
→ visual review
→ keep, revise, delete, or bind to music
```

## Generate a native scene

The **Native scene direction** panel does not read a source image. Describe how the scene and camera evolve over time, not merely what one frame contains. Choose a four-, eight-, or twelve-second study. Preview binds the direction, seed, duration-specific FastWan profile, dimensions, frame count, 24 fps output, estimated runtime, and three-step schedule. **Generate exact native scene** starts one foreground render with a 17½-minute hard timeout.

The result enters the normal motion candidate list. Diffusion remains on AMD Vulkan; native video decoding uses bounded VAE tiling on CPU so the complete study does not require one device-sized Vulkan buffer. Four- and eight-second studies are generated directly at 24 fps. The twelve-second profile bounds model work to 193 frames at 16 fps, then performs one local optical-interpolation pass to produce the 289-frame, 24 fps review artifact. Review it for camera coherence, geometry stability, interpolation artifacts, flicker, banding, pacing, and its likely loop boundary. Only a `keep` review unlocks Music binding.

The existing **Create motion study** action remains the image-guided route and requires a kept still.

### Qualification ledger

The right-side **Qualification ledger** reads retained motion receipts and
human reviews. It groups evidence across the supported four-, eight-, and
twelve-second durations and shows sample counts, reviewed counts, keep/revise
counts, average human rating, render elapsed time, and runtime per output
second. It is a read-only comparison surface: it does not infer visual quality,
change a review, qualify a profile, or start a render.

Use the ledger to decide whether added duration or interpolation produces
enough visible benefit to justify its runtime and resource cost. Missing or
unreviewed evidence remains explicit.

### Native scenes through Chat

After a Chat-created visual receives a `keep` review—or Chat resolves an exact
existing kept Visual Studio project—you may ask Soul to generate a native
scene. Supply a chronological direction and a 4-, 8-, or 12-second duration.
Chat shows the exact seed, profile, frame envelope, estimated runtime, and Core
transition before one action click. The WebM returns to Chat but remains a
Visual Studio candidate.

Record motion review here. If disposition is `revise`, Chat can prepare the
next linked native revision from explicit replacement direction. Motion
review, image-guided motion, binding motion to music, and deletion retain their
Visual Studio controls.

## Build an editable Blender scene

**Whole-bar Blender companion** is the source-editable procedural lane. It
requires one exact Music candidate whose human review is `keep`. Choose a
reviewed scene family, a closed **Look profile**, an 8- or 12-musical-bar span,
review or production resolution, and a deterministic seed. Creative direction is retained with the
candidate as intent and revision evidence, but it does not silently rewrite
the trusted template.

Preview binds the exact music digest, review digest, BPM, meter, whole-bar
duration, frame count, template, look profile, render profile, seed, manifest digest,
analysis digest, and resource lease. Execution then:

1. derives bounded low-, mid-, high-band, energy, and kick curves from the
   exact lossless song candidate;
2. constructs a new `.blend` through the repository-owned adapter;
3. renders a verified PNG frame sequence through EEVEE;
4. encodes the exact whole-bar MP4 loop with source audio only after every
   frame exists; and
5. returns the MP4, still, editable `.blend`, manifest, and audio evidence for
   human review.

The available scene families are **Willow fungal grove**, **Void sanctuary**, **Signal forge**,
**Bioluminescent grove**, **Audio reactive chamber**, **Architectural**,
**Liminal**, and **Abstract**. Look profiles can retain the template treatment
or apply reviewed cinematic-organic, liminal-haze, signal-forge, or
crystalline-void combinations. Those combinations select only trusted surface,
atmosphere, camera-depth, glow, and AgX grading presets inside Soul's adapter.
They do not accept node graphs or Blender code from the model or browser.

**Willow fungal grove** exercises the first trusted procedural-organics
vocabulary. Its willow is constructed from bounded tapered curves, hierarchical
drooping branches, visible roots, and combined leaf geometry. Its fungal
clusters use curved tapered stems, revolved cap profiles, and radial underside
gills. The manifest selects only reviewed archetypes, material roles, seeds,
and bounded parameters; all Blender geometry remains repository-owned.

Scene families remain reusable art directions, not unrestricted text-to-3D.
Character rigs, arbitrary add-ons, downloaded `.blend` auto-execution,
arbitrary asset paths, and model-authored Python remain unsupported.

Record a 1–5 `keep` or `revise` review. A revision is a new immutable scene;
the source remains available. A failed partial frame set can be resumed only
through its explicit exact gate. A kept scene can be bound only to the music
candidate that supplied its audio evidence. Continue in Music Studio to render
the full-duration loop and prepare the normal private YouTube package.

Chat and Voice can explain this lane and enumerate its required inputs through
the shared capability catalog. First-generation scene construction remains a
Visual Studio action in A5; conversation does not silently compile geometry or
start Blender.

## Review a candidate

Each candidate records its generation kind, elapsed time, immutable input, and image artifact. Review it with a 1–5 rating, a keep/revise disposition, and notes explaining what worked and what should change.

### Guided revision

**Image-guided revision** starts from one exact candidate. Describe the change while naming what must remain invariant—for example, preserve composition and architecture while changing atmosphere or a distant element. A new seed and exact preview bind the edit. The source candidate remains intact.

For a native scene, record a `revise` motion review. **Revise native scene** then preloads those review notes as the next chronological scene direction. You may edit the direction, choose four, eight, or twelve seconds, and preview the exact new seed and profile before rendering. The revision is a new immutable candidate linked to its source; it does not overwrite the prior clip.

### Delete a candidate

Candidate deletion is permanent and separately previewed. A full project deletion inventories and removes the brief, revisions, candidates, images, logs, and reviews. A visual already copied into Music Studio lineage remains attached there.

## Bind artwork to music

**Bind to Music candidate** selects an exact Music Studio project and generated candidate, previews the binding, and copies the reviewed still into that candidate's visual lineage. It does not render video or publish anything.

Continue in [Music Studio](MUSIC_STUDIO.md) to choose static framing, matte, fades, render the full-length companion MP4, and prepare a local upload package.

## Prompt guidance

State the scene and visual hierarchy before surface detail. Strong prompts usually identify:

1. subject and environment;
2. camera/framing and focal placement;
3. lighting, mood, and palette;
4. medium or rendering character;
5. details to preserve or exclude.

Avoid asking one candidate to reconcile many incompatible aesthetics. Use guided revision for targeted changes rather than repeatedly expanding the original prompt.

## Related engineering references

- [`docs/soul/VISUAL_STUDIO_A0_A1_BRIEF.md`](../soul/VISUAL_STUDIO_A0_A1_BRIEF.md)
- [`docs/soul/VISUAL_STUDIO_A2_BRIEF.md`](../soul/VISUAL_STUDIO_A2_BRIEF.md)
- [`docs/soul/MUSIC_VISUAL_COMPANION_A4_STATIC_PRESENTATION_BRIEF.md`](../soul/MUSIC_VISUAL_COMPANION_A4_STATIC_PRESENTATION_BRIEF.md)
- [`docs/soul/VISUAL_STUDIO_A4_GENERATED_MOTION_BRIEF.md`](../soul/VISUAL_STUDIO_A4_GENERATED_MOTION_BRIEF.md)
- [`docs/soul/VISUAL_STUDIO_A5_NATIVE_VIDEO_BRIEF.md`](../soul/VISUAL_STUDIO_A5_NATIVE_VIDEO_BRIEF.md)
