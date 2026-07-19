# Music Studio 600-Second Production Promotion Brief

## Objective

Promote the accepted ten-minute ACE-Step Vulkan duration into Soul's production Music Studio as one exact preset: 600 seconds.

## Evidence

The exact-gated qualification produced a 600.0-second, 48 kHz stereo instrumental in 97.8 seconds. Its audio-code plan passed deterministic collapse checks, no long silence or resident process remained, and the Operator accepted its sustained coherence and restrained late development around 6:20.

## Boundary

- Supported new-project durations become exactly 30, 90, 180, and 600 seconds.
- Arbitrary durations and the unpromoted 210-second qualification remain unavailable in Music Studio.
- Ten-minute generation is available only through the existing AMD Vulkan production backend and Music Core resource lane.
- One candidate, batch size 1, eight inference steps, VAE chunk 256, no offload, and three bounded LM-plan attempts remain unchanged.
- The 600-second-only terminal-code normalization is retained in production evidence.
- Project creation, generation, revision, review, deletion, trimming, export, and visual-companion workflows retain their existing human gates and lifecycle behavior.
- Navigation may detach the dashboard from a durable job, but no new daemon, watcher, listener, schedule, or unbounded polling behavior is introduced.

## Acceptance

- The dashboard offers a clearly labeled 10-minute preset.
- Storage and schema validation accept 600 but continue rejecting arbitrary durations.
- Core status reports 600 as supported.
- Production generation records the exact terminal-code normalization in candidate evidence.
- Existing shorter durations and the separate 210-second qualification continue to pass deterministic tests.
- Documentation teaches the expanded duration without implying arbitrary long-form generation.

## Risk

Risk classification: local compute and storage, medium. A ten-minute candidate occupies the AMD lane longer and creates larger FLAC/MP3 and optional visual artifacts, but execution and retries remain bounded and human-authorized.
