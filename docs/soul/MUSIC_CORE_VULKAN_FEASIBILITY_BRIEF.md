# Music Core Vulkan Feasibility Brief

```text
date: 2026-07-18
human_authorization: approved in the active development conversation
implementation_authorized: yes
model_download_authorized: yes, only the exact candidate files below
live_core_transition_authorized: no; preserve the existing Core gate
production_generation_change_authorized: only after measured pilot acceptance
risk: Class 3 - bounded local runtime and GPU mutation
```

## Objective

Determine whether the RX 6900 XT can run a materially stronger ACE-Step 1.5
music-planning configuration through a native Vulkan foreground process while
Chat moves to the existing NVIDIA fallback. If and only if the measured pilot
passes, integrate the accepted profile as Music Core's generation engine and
make new 180-second generation available only in Music Core. Daily Core remains
limited to 30- and 90-second new work.

Existing projects and candidates remain readable and reviewable regardless of
Core. The duration policy applies to project creation and generation/revision
eligibility, never destructive migration.

## Candidate rationale

The current NVIDIA path uses ACE-Step 1.5 2B Turbo with the 0.6B LM on a GTX
1070. The strongest no-offload candidate that plausibly fits the 16 GiB AMD
lane is the 4B ACE-Step LM with the 2B Turbo DiT, using Q8_0 GGUF weights and a
BF16 VAE. This targets composition planning, lyric/audio-code generation, and
structural adherence. It is not the XL 4B DiT: the official host tier guidance
requires offload for XL on this card, which is outside this candidate.

The Vulkan implementation is a community C++/GGML backend, not the official
Python inference implementation. Therefore functional parity and audio quality
must be measured rather than inferred from the model names.

## Exact source and model boundary

```text
runtime repository: https://github.com/ServeurpersoCom/acestep.cpp.git
runtime revision: 7eb27775fd110a8b2503ac089aedcc02416caa0a
GGML submodule revision: 9e2947f17583acc2f657a77c29b6593ca0fbc6c4
model repository: Serveurperso/ACE-Step-1.5-GGUF
model revision: 9b3707625776cc4cf775e9b12ab82f9fe48335ff
```

The exact filenames, sizes, and SHA-256 values live in
`config/music_vulkan_pilot_models.json`. Downloads must use revision-pinned
URLs, reject redirects outside HTTPS, write `.partial` files, verify size and
digest, and rename atomically. A mismatch fails closed.

## Authorized vertical slice

- Add a versioned, user-local checkout and build below
  `~/.local/share/soul/music/acestep-cpp/<revision>/`.
- Build only a Vulkan/CPU command-line runtime from the pinned source and
  submodule; do not build or launch its HTTP server or browser UI.
- Download only the four manifest-pinned GGUF files needed for the candidate.
- Add bounded `check`, `plan`, `setup`, `download`, and `run` foreground
  commands with exact digest/confirmation gates on mutations.
- Run a deterministic binary/model inspection before any audio pilot.
- Require the existing Music Core transition gate to release AMD chat before a
  live Vulkan pilot. Do not stop, switch, or start Chat implicitly.
- Represent Music Core as an explicit operating intent over the already
  configured NVIDIA reserve-chat profile when no dedicated `music-chat`
  profile exists. Do not duplicate a service record or conflate Music Core
  with AMD-Free Core; persist the exact active intent in bounded Core state.
- Begin with one 30-second pilot; proceed to 90 seconds only after runtime,
  artifact, and human listening checks pass. The Operator accepted the
  30-second result on 2026-07-18 and explicitly authorized one comparative
  90-second and one comparative 180-second pilot using the same creative
  input, synthesis settings, seed, and LM seed. No other 180-second
  feasibility run is authorized by this brief.
- Record wall time, exit status, model identities, artifact size/duration,
  process termination, and human listening observations.
- Inspect LM audio-code health before synthesis. Within one confirmed
  foreground generation, a globally collapsed plan is discarded before
  synthesis and the LM may retry with a deterministically derived new seed.
  At most three total LM attempts are allowed. Three consecutive collapses
  stop at `blocked_for_human_review` with all attempt evidence; synthesis is
  never started. No additional confirmation is required for those two bounded
  internal retries. Localized repetition alone remains review evidence rather
  than a hard failure so sustained musical endings are not rejected
  indiscriminately.
- Pin VAE decode tiles to 256 latent frames. The accepted 30-second default-
  chunk run completed, but the first 90-second comparison reached a
  1024-frame VAE tile and caused an AMD compute-ring timeout. The kernel reset
  succeeded and no child survived. A corrected comparison series requires a
  fresh digest-bound confirmation because this decoder setting changed.
- After acceptance, expose exact engine and Core duration availability through
  the existing event-driven dashboard surfaces.

## Lifecycle and bounds

Every pilot command terminates as one of:

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

Build and downloads have explicit timeouts and byte limits. Each generation is
a single foreground process group with a timeout, interrupt handling, bounded
logs, and owned-child termination. No process survives command return.

## Hard boundaries

- No service, systemd unit, daemon, watcher, listener, queue, scheduler,
  polling loop, or background continuation. The only automatic retry is the
  explicitly approved in-process LM-plan collapse recovery above: two retries,
  three total attempts, before any synthesis. No synthesis, process, download,
  Core transition, or whole-operation retry is automatic.
- No automatic Core transition, model preemption, fallback, or restoration.
- No XL DiT, CPU/GPU offload, ROCm installation, driver change, system package
  installation, model training, LoRA, reference-audio cloning, or publishing.
- No use of upstream `server.sh`, `ace-server`, browser UI, automatic model
  downloader, update script, or unpinned `models.sh` download behavior.
- No weakening of the current generation/revision confirmation, lease,
  cancellation, artifact validation, review, export, or deletion gates.
- No promotion based only on successful execution; human listening and
  workflow review remain authoritative.

## Acceptance gates

```text
[x] pinned source and submodule exactly match
[x] build contains Vulkan and identifies RX 6900 XT
[x] every model file matches the pinned size and SHA-256
[x] no Chat or music lease is active before Core transition
[x] 30-second run terminates and leaves no child process
[x] 30-second WAV inspection proves 48 kHz stereo and expected duration
[x] Operator judges 30-second audio useful enough to continue
[x] 90-second run terminates and leaves no child process
[x] 90-second artifact and resource evidence pass
[x] 180-second comparative run terminates and leaves no child process
[x] 180-second artifact and resource evidence pass
[ ] Operator compares structural and lyric adherence against the current path
[ ] production integration and 180-second Music Core policy receive review
```

## Human review outcome

```text
Outcome: implementation and exact feasibility setup authorized
Reviewer: repository owner
Date: 2026-07-18
Decision summary: Proceed with the next Core-aware larger ACE-Step slice.
```
