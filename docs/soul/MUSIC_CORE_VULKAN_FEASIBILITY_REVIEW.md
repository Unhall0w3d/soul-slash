# Music Core Vulkan Feasibility Review

## Candidate

```text
Name: Music Core ACE-Step Vulkan feasibility
Risk class: Class 3 - bounded local runtime and GPU mutation
Branch/checkpoint: main working tree; not committed
Date: 2026-07-18
Status: candidate_complete; promoted through the approved production brief
```

## Implementation summary

Added a revision-pinned native Vulkan ACE-Step feasibility lane for the RX
6900 XT using the 4B LM, 2B Turbo DiT, Q8 embedding, and BF16 VAE. Setup,
downloads, and foreground pilots are digest-bound and confirmation-gated. The
runtime starts only for the invoked command and terminates on completion,
failure, cancellation, or timeout.

Added a deterministic pre-synthesis audio-code health gate after listening
review identified that the first 90-second plan had collapsed. The gate checks
global uniqueness, adjacent repetition, dominant-token share, and expected
5 Hz code count. Within one confirmed foreground run, a collapsed plan is
discarded before synthesis and retried with a deterministic new LM seed. The
operation permits three total LM attempts, retains evidence for each, and
stops at human review without synthesis after a third consecutive collapse.

The first 30-second run exposed missing local shared-library resolution and an
unsupported generic WAV output label; both failed closed and were repaired.
The first 90-second run used upstream's 1024-frame VAE tile default and caused
an AMD compute-ring timeout. The kernel reset succeeded, the desktop remained
responsive, no child survived, and both GPUs enumerated normally afterward.
The profile now pins the reference-sized 256-frame VAE tile. Corrected 30-,
90-, and 180-second runs then completed successfully.

## Files changed

```text
- Makefile
- config/music_vulkan_models.json
- docs/soul/MUSIC_CORE_VULKAN_FEASIBILITY_BRIEF.md
- docs/soul/MUSIC_CORE_VULKAN_FEASIBILITY_REVIEW.md
- lib/soul_core/core_orchestration_service.rb
- scripts/soul-music-vulkan-pilot
- scripts/verify-core-orchestration.rb
- scripts/verify-music-core-vulkan-feasibility.rb
```

## Commands run and deterministic results

```text
ruby -c scripts/soul-music-vulkan-pilot
PASS

ruby scripts/verify-music-core-vulkan-feasibility.rb
PASS, including collapsed/diverse/localized-outro code-health fixtures and
the exact three-attempt recovery boundary

make music-vulkan-check
PASS: exact source, binaries, four model sizes/digests, no persistent process

ruby scripts/verify-core-orchestration.rb
PASS (run earlier in this slice; rerun required before candidate completion)

git diff --check
PASS

30-second chunk-256 pilot
PASS: 9.34s wall; 30.0s; PCM s16le; 48 kHz stereo; SHA-256
34e42873fe2463161ce7c7f49fdf0ebf750117663eb7b4215603af4dece42f7c
Byte-identical to the accepted default-chunk 30-second pilot.

90-second chunk-256 pilot
PASS: 17.97s wall; 90.8s; PCM s16le; 48 kHz stereo; SHA-256
23f8ad71fc75e1ebf8240d4a1785f406038927d1da0a88e1709a5d860bc5cfdb

180-second chunk-256 pilot
PASS: 32.5s wall; 179.2s; PCM s16le; 48 kHz stereo; SHA-256
39a4276cb520061f3c48e857c48b719bca9db49b11d2346347ffb8cc68a4fcd9
Operator observation: slow build, but recognizably cohesive as a song.

Post-listening 90-second plan analysis
FAIL (musical plan): 57 unique codes out of 454 (12.6%); 74.4% of
adjacent codes repeat; one identical-code run spans approximately 19 seconds.
Only the final 5.8 seconds return to high code diversity. CPU Whisper detects
voice-like material only at 83.1-86.9 seconds. Essentia estimates roughly
150 BPM / F major rather than the requested 110 BPM / D minor. The VAE
faithfully rendered a degenerate LM plan; Vulkan chunking did not cause it.

Bounded 90-second collapse-recovery pilot
PASS: attempt 1 reproduced and rejected the known collapsed plan before
synthesis (seed 407078830; 12.6% unique; 74.4% adjacent repetition; 67.0%
dominant-token share). Attempt 2 used seed 219315719 and passed (94.3% unique;
3.5% adjacent repetition; 1.8% dominant-token share). Only attempt 2 was
synthesized. Output completed in 27.46 seconds wall time as 90.64-second,
48 kHz stereo PCM with SHA-256
58e82988d3d9c657520883a962139cad8546add9b1b2a4e98683cf63e036ae29.
No ACE process survived. Essentia estimated 107.8 BPM and D minor, closely
matching the requested 110 BPM / D minor, with a rise-and-fall energy curve.

Post-listening 180-second plan analysis
PASS (provisional): 754 unique codes out of 896 (84.2%); only 8.8% adjacent
repetition. The stream remains highly diverse through approximately 165
seconds, followed by a 13.6-second repeated-code tail consistent with a
possible sustained outro. Operator reports the full result is cohesive.

Post-run process and Vulkan inspection
PASS: no ace-lm or ace-synth process; RX 6900 XT and GTX 1070 enumerate
```

## Local LLM eval results

```text
Not applicable. These pilots measure a pinned music LM/DiT/VAE runtime and
human listening quality, not Soul conversational behavior or safety policy.
```

## Failures encountered

```text
1. libggml-vulkan.so.0 was not found until the launcher bounded
   LD_LIBRARY_PATH to the verified build directory.
2. Upstream accepts wav16/wav24/wav32, not generic wav; pinned to wav16.
3. The first 90-second VAE decode reached T_latent=1024 and the kernel logged
   an ace-synth comp_1.1.1 ring timeout. Ring reset succeeded. Pinning
   --vae-chunk 256 produced 6, 18, and 35 bounded tiles for 30/90/180 seconds.
```

## Memory keys

```text
Reads: none
Writes/updates: none
Forget behavior: not applicable
```

## Lifecycle states touched

```text
- complete
- failed
- canceled (implemented, not exercised)
- awaiting_input (validation/plan behavior)
- blocked_for_human_review
```

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Network listener added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Known weaknesses

```text
- Listening quality, structure, and lyric adherence for 90/180 seconds still
  require final Operator review. The first 90-second plan is rejected as
  degenerate; the 180-second plan is provisionally cohesive.
- The same bounded degeneration guard now protects the production Music Studio
  path before VAE synthesis.
- The community Vulkan backend is not the official ACE-Step Python runtime.
- 256-frame VAE tiles trade some throughput for shorter GPU kernels; seams
  must be assessed by listening even though the 30-second output was identical.
- Failed or collapsed attempts are retained for human diagnosis; a separate,
  explicit retention/discard surface is still needed to prune that evidence.
- The community Vulkan backend is pinned and verified, but remains an upstream
  dependency whose future revisions require a new qualification pass.
```

## Human review checklist

```text
[x] 90-second track reviewed; reject degenerate LM plan
[x] 180-second track is musically useful and free of reported tile seams
[x] Structural quality justifies promoting this path with continued human review
[x] Production integration scope is approved
[x] No unapproved persistence or scope expansion
[x] Confirmation and failure behavior are acceptable
[x] Full deterministic regressions pass
```

## Human review outcome

```text
Outcome: approved for production integration
Reviewer: repository owner
Date: 2026-07-18
Decision summary: 30-second output accepted; 90-second LM plan rejected;
  corrected 90-second output strongly accepted; 180-second output reported
  cohesive; production integration approved
Required changes: add pre-synthesis LM audio-code degeneration detection and
  bounded automatic new-seed recovery (implemented in production)
```
