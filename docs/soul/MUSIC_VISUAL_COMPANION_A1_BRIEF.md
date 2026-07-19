# Music Visual Companion A1 — Three-Minute Proof

## Objective

Bind one reviewed visual source to one exact generated music candidate, render a short deterministic environmental loop, and compose one local three-minute audiovisual preview for human review.

## Scope

- Preserve the source project ID, candidate ID, FLAC digest, visual-source manifest digest, image digest, provider, and rights status.
- Use a 12-second 1280×720, 30 fps procedural loop with periodic camera drift and localized foreground-water displacement.
- Measure first-to-last-frame PSNR as seam evidence.
- Repeat the approved loop against the exact lossless candidate audio.
- Apply a two-second visual fade-in and four-second visual fade-out.
- Produce a private local H.264/AAC MP4 preview.
- Expose source binding, loop render, and final render as separate exact click-authorized gates in Music Studio.

## Boundaries

- No local image model is installed or loaded.
- No Gemma call is made in A1.
- No generative video model is used.
- No background queue, listener, automatic retry, upload, YouTube integration, publication, or long-form mix is added.
- The visual remains bound to the immutable candidate version even when a newer music revision exists.

## Lifecycle

Every operation terminates as `complete`, `awaiting_input`, `failed`, `canceled`, or `blocked_for_human_review`. Rendering is a bounded foreground FFmpeg operation with a ten-minute timeout.

## Risk

Low. A1 writes only project-local visual derivatives and does not modify music candidates or external files.
