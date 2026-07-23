# Visual Studio A5: native text-to-video

## Objective

Add one practical, bounded text-to-video path beside the existing still and image-guided motion paths. The Operator supplies a cinematic scene direction and seed; the renderer creates motion without receiving a source image.

## Approved flow

1. Select a Visual Studio project to provide intent and archive ownership.
2. Enter a chronological scene direction and seed.
3. Preview binds the project digest, direction, seed, pinned FastWan profile, dimensions, frames, frame rate, and three-step schedule.
4. `GENERATE_NATIVE_VIDEO` authorizes one foreground AMD/Vulkan invocation with a 1,050-second hard timeout and no automatic retry. The invocation acquires the same exclusive AMD-generation lease used by Music Studio; an occupied lane fails immediately and is never queued.
5. The resulting WebM, bounded log, receipt, and text-to-video lineage enter the same immutable motion-candidate archive used by image-guided motion.
6. Human `keep` or `revise` review remains mandatory. A `revise` review unlocks a new exact native-scene revision preview using the recorded notes, a new seed, and a four-, eight-, or twelve-second profile. The prior clip remains immutable and the revision records its source candidate.
7. Only `keep` can advance to the existing exact Music candidate binding and full-duration render gates.

## Fixed production envelope

- FastWan 2.2 TI2V 5B FullAttn Q6_K.
- 832×480 at 24 fps delivery, three Euler/LCM steps, CFG 1. The twelve-second profile generates 193 frames at 16 fps and derives the 289-frame review artifact through bounded local optical interpolation.
- Four, eight, or twelve seconds of native video. A three-minute companion repeats the exact accepted clip; the system does not claim to synthesize 180 unique seconds.
- Runtime varies by duration, runtime build, and decoder placement. The exact approval scope exposes the selected envelope; the 1,050-second hard timeout is authoritative.
- AMD-Free Core or Music Core; foreground invocation exits and releases its shared AMD-generation lease at success, failure, cancellation, or timeout.

## Boundaries

- No source still is supplied to the native renderer.
- No daemon, listener, queue, watcher, scheduler, background model process, automatic retry, upload, or publication. Music and Visual Studio renders cannot overlap on AMD.
- No multi-shot storyboarding, temporal extension, interpolation, or silent aesthetic approval in this slice.
- Existing image-guided motion remains unchanged.

## Acceptance

- Real qualification produces a valid coherent WebM from text alone within the timeout.
- Deterministic fixtures prove exact approval, no image argument, fixed distilled schedule, immutable revision lineage, duration bounds, and reuse of human motion review.
- Dashboard exposes native video separately and accurately identifies text-to-video candidates.
