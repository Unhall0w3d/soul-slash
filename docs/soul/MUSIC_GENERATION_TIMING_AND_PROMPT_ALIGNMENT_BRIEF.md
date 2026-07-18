# Music Generation Timing and Prompt Alignment Brief

## Objective

Persist useful generation-performance evidence and align Soul's production prompt contract with the official ACE-Step 1.5 documentation and the exact pinned `acestep.cpp` runtime.

## Timing contract

Each successfully published candidate records:

- wall-clock start and completion timestamps;
- bounded foreground model time, including LM planning and synthesis;
- WAV-to-FLAC derivation time when the Vulkan backend is active;
- FLAC-to-MP3 derivation time;
- total foreground wall time.

Durations use a monotonic clock, are rounded to milliseconds, and are review evidence rather than performance guarantees. Candidate cards show the total and a phase breakdown. Existing candidates without timings remain readable.

## Prompt contract

- Sound and Structure is one coherent overall portrait no longer than the runtime's documented 512-character caption limit.
- Prefer one primary genre center. Express compatible secondary influence as instrumentation, harmony, rhythm, texture, or production—not an equal-priority genre list.
- Avoid conflicting instructions. When contrast is necessary, describe a broad evolution rather than simultaneous incompatible styles.
- Vocal projects use concise, moderate structure tags consistent with the caption. Lyrics should generally use short, rhythmically comparable lines.
- Instrumental projects store no lyrics and send exact `[Instrumental]` to the pinned runtime.
- Soul's language field is mapped to the runtime's `vocal_language`; instrumental requests use `unknown`.
- BPM, key, dominant time signature, duration, and seed remain dedicated fields.
- Batch size remains one. Trying another interpretation is a new exact-gated generation rather than an automatic batch.

## Sources

- ACE-Step 1.5 Tutorial: https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/Tutorial.md
- ACE-Step 1.5 Inference API: https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/INFERENCE.md
- ACE-Step 1.5 Musician's Guide: https://github.com/ace-step/ACE-Step-1.5/blob/main/docs/en/ace_step_musicians_guide.md
- Pinned `acestep.cpp` architecture and request parser under the verified local runtime revision.

## Boundaries

This slice does not add batching, automatic retries beyond the existing collapse guard, reference-audio conditioning, repainting, a new model, a service, a queue, or background work. Repaint and a Base/SFT final-quality lane remain future candidates for separate hardware and governance review.

## Risk

Risk classification: low. Timing adds bounded receipt metadata. Prompt alignment narrows new and revised captions and corrects runtime conditioning without weakening human gates.
