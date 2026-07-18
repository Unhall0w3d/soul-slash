# Music Vulkan 210-Second Qualification Brief

## Objective

Qualify one 210-second ACE-Step Vulkan pilot before deciding whether 3 minutes 30 seconds belongs in Soul's production Music Studio duration contract.

The qualification composition is an original instrumental stress test informed by broad, non-exclusive traits observed in the operator-supplied recording of `Tank!`: fast Latin-funk propulsion, big-band brass and reeds, independent ensemble lines, featured improvisation, and a precise ensemble ending. It must not reproduce the source melody, recording, spoken introduction, or other expressive content.

## Boundary

- Production project durations remain exactly 30, 90, and 180 seconds.
- Only the foreground Vulkan pilot accepts 210 seconds.
- A 210-second request must contain the exact marker `duration_210_v1`.
- The marker is included in the preview digest and therefore cannot be added or changed after approval.
- A production-duration request must not carry a qualification marker.
- One output, batch size 1, eight inference steps, no offload, and VAE chunk 256 remain unchanged.
- LM collapse detection may retry automatically with a derived seed, but stops after three consecutive collapsed plans without beginning synthesis.
- The exact `RUN_MUSIC_VULKAN_PILOT` confirmation and preview digest remain required.
- Execution is bounded and foreground. No service, daemon, listener, watcher, or scheduled work is added.

## Stress composition

The pilot should test whether 210 seconds can sustain:

- a fast rhythm-section pocket without collapsing into repeated audio codes;
- distinct saxophone and brass roles rather than a single undifferentiated horn pad;
- several density changes and an improvised solo feature;
- interlocking ensemble counterpoint during the late climax;
- a deliberate short stinger ending without an accidental tail;
- instrumental-only output with no spoken or sung material.

The ACE-Step caption describes the sonic identity. Section order and performance changes belong in the section-marker script.

## Acceptance

Technical acceptance requires exactly one non-empty 48 kHz stereo WAV within two seconds of 210 seconds, a non-degenerate LM plan, bounded terminal completion, retained diagnostic evidence, and no resident process.

Technical acceptance does not promote the duration. Human listening review must assess coherence, genre fit, section differentiation, ensemble clarity, ending quality, and any audible collapse or repetition before a separate production decision.

## Risk

Risk classification: local compute and temporary storage, medium. The longer synthesis increases GPU occupancy and failure cost but does not authorize persistence, publication, source retention, or production use.
