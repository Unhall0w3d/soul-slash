# Music Vulkan 600-Second Qualification Brief

## Objective

Qualify one ten-minute ACE-Step Vulkan instrumental before deciding whether longer-form composition belongs in Soul's production Music Studio duration contract.

The pilot is an original Melodic Techno and Deep House composition intended to test long-range pacing, motif continuity, controlled evolution, and ending quality rather than genre density or vocal adherence.

## Boundary

- Production project durations remain exactly 30, 90, and 180 seconds.
- Only the foreground Vulkan pilot accepts 600 seconds.
- A 600-second request must contain the exact marker `duration_600_v1`.
- The marker is included in the preview digest and cannot be added or changed after approval.
- One output, batch size 1, eight inference steps, no offload, and VAE chunk 256 remain unchanged.
- LM collapse detection may retry automatically with a derived seed, but stops after three consecutive collapsed plans without beginning synthesis.
- The pinned LM emits 3,001 codes for a 600-second request while the synthesizer accepts exactly 3,000 codes / 15,000 latent frames. Only for this qualification, one excess terminal code may be removed deterministically and the adjustment must appear in retained evidence.
- The exact `RUN_MUSIC_VULKAN_PILOT` confirmation and preview digest remain required.
- Execution is bounded and foreground. No service, daemon, listener, watcher, scheduled work, or production-duration promotion is added.

## Stress composition

The pilot should test whether 600 seconds can sustain:

- a stable 122 BPM four-on-the-floor pulse without short-loop collapse;
- recognizable analog arpeggio, bass, pad, percussion, and lead-motif roles;
- patient movement from sparse opening through layered groove and harmonic lift;
- a controlled breakdown followed by a distinct late peak;
- enough variation to avoid sounding like one short section repeated;
- a deliberate resolved outro rather than an abrupt cutoff;
- instrumental-only output without spoken or sung material.

The caption defines one coherent sonic identity. Section markers communicate only broad progression and do not demand second-by-second choreography.

## Acceptance

Technical acceptance requires exactly one non-empty 48 kHz stereo WAV within two seconds of 600 seconds, a non-degenerate 3,000-code synthesis plan within the existing tolerance, explicit evidence if the LM's single excess terminal code was removed, bounded terminal completion, retained diagnostic evidence, and no resident process.

Technical acceptance does not promote ten minutes into Music Studio. Human listening review must assess global coherence, repetition, motif continuity, transitions, dynamic development, ending quality, unintended vocals, and any audible generation collapse.

## Risk

Risk classification: local compute and temporary storage, medium. The longer synthesis increases GPU occupancy, output size, and failure cost, but does not authorize persistence, publication, production use, or automatic retry beyond the existing three-plan collapse bound.
