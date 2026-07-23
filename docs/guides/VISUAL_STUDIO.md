# Visual Studio

Visual Studio is Soul's private local image and short-scene workshop. It records a visual brief, generates immutable still or motion candidates through bounded Vulkan lanes, supports guided revisions and review, and can bind one exact accepted visual to one Music Studio candidate.

Open it from **Creative Studios → Visual Studio**.

## Current production boundary

The supported still lane uses the reviewed FLUX.2 Klein Vulkan profile. Image-guided motion uses Wan 2.2; native text-to-video uses the distilled FastWan 2.2 profile. Each model is loaded for one foreground render and exits afterward. There is no resident image server, automatic publication, or silent promotion into Music Studio.

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
