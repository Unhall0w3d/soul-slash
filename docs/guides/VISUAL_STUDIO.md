# Visual Studio

Visual Studio is Soul's private local still-image workshop. It records a visual brief, generates immutable candidates through a bounded Vulkan lane, supports guided revisions and review, and can bind one exact image to one Music Studio candidate.

Open it from **Creative Studios → Visual Studio**.

## Current production boundary

The supported lane is local still generation with the reviewed FLUX.2 Klein Vulkan profile. The model is loaded for one foreground render and exits afterward. There is no resident image server, automatic publication, or silent promotion into Music Studio.

Generated motion remains a qualification track rather than a production feature. Historical FFmpeg motion-effect experiments remain evidence only; the accepted music companion presentation currently holds the reviewed image static and uses FFmpeg only for framing, fades, encoding, and audio muxing.

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

## Review a candidate

Each candidate records its generation kind, elapsed time, immutable input, and image artifact. Review it with a 1–5 rating, a keep/revise disposition, and notes explaining what worked and what should change.

### Guided revision

**Image-guided revision** starts from one exact candidate. Describe the change while naming what must remain invariant—for example, preserve composition and architecture while changing atmosphere or a distant element. A new seed and exact preview bind the edit. The source candidate remains intact.

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
