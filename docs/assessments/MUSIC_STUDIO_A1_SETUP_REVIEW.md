# Music Studio A1 Setup Boundary Review

Status: approved and complete

Date: 2026-07-17

## What was implemented

- Added `uv`, FFmpeg, and NVIDIA detection as optional Music tooling without
  making them general Soul prerequisites.
- Added Make targets for Music preflight, exact preview, isolated environment
  setup, separately confirmed model download, and bounded foreground pilots.
- Pinned ACE-Step v0.1.8, Python 3.12, the recommended 2B turbo / 0.6B model
  pair, exact Hugging Face revisions, file sizes, and SHA-256 digests.
- Added exact case-sensitive model and manifest overrides. Unknown names fail
  closed; URLs are constructed from validated Hugging Face repository names.
- Kept the upstream lock for non-PyTorch dependencies while substituting the
  PyTorch 2.10 CUDA 12.6 wheels needed for Pascal SM 6.1, followed by a real
  synchronized CUDA matrix multiplication and compatible-cubin probe. PyTorch's
  wheel exposes `sm_60`; NVIDIA guarantees that cubin on the higher-minor
  desktop `sm_61` device within the same major architecture.
- Added an offline-only, foreground 30/90/180-second pilot command with fixed
  batch, seed, backend, offload, quantization, and timeout behavior.
- Added an exact v0.1.8 compatibility overlay that implements the release's
  advertised Pascal float32 recovery, bypasses automatic download and code-sync
  paths under Soul's strict-offline flag, and retains only explicitly reviewed
  pilot output.
- Hardened success detection: profiler exit zero is insufficient unless the log
  is failure-free and a non-empty audio artifact is retained.
- Fixed Self Assessment reboot evidence using the exact CachyOS hook message
  relative to current boot time; old, missing, and unsafe evidence fails
  honestly without rebooting the host.

## Files changed

- `Makefile`
- `config/music_pilot_models.json`
- `scripts/soul-music-pilot`
- `scripts/soul-runtime-check.sh`
- `scripts/verify-music-studio-a1-setup.rb`
- `scripts/verify-multi-model-music-studio-a0.rb`
- `lib/soul_core/package_manager_assessor.rb`
- `lib/soul_core/environment_assessor.rb`
- `scripts/verify-environment-reboot-recommendation.rb`
- Music A1 brief, review, setup documentation, roadmap, and current-state docs.

## Commands run

- Ruby syntax checks for changed Ruby files.
- `ruby scripts/verify-environment-reboot-recommendation.rb`
- `ruby scripts/verify-music-studio-a1-setup.rb`
- `make check`
- `make music-check`
- `make music-pilot-plan`
- Approved `make setup-music` with the reviewed digest and exact confirmation.
- Live ACE-Step import plus synchronized CUDA matrix probe.
- Approved 30-second pilot, failure diagnosis, exact overlay application,
  checkpoint repair/reverification, and final audio/mechanical review.
- Post-pilot manifest verification of all 7,709,375,886 checkpoint bytes.
- Existing environment and host-improvement verifiers.
- Live read-only NVIDIA, fallback service, and reboot-evidence checks.
- `git diff --check`

## Deterministic test results

The setup verifier covers exact defaults and overrides, source and runtime
pins, 7,709,375,886 explicitly planned model bytes, separate confirmation
gates, write-free rejection, optional `uv` reporting, offline foreground
execution, duration bounds, and the Pascal CUDA probe. The reboot verifier
covers recommendations after boot, stale recommendations before boot, hook runs
without the message, missing logs, and symlink rejection.

Result: pass.

## Approved live setup result

After owner approval, the setup gate installed the exact ACE-Step v0.1.8
revision and isolated Python 3.12 environment under
`~/.local/share/soul/music/ace-step/v0.1.8`. The final probe reported:

```text
PyTorch: 2.10.0+cu126
CUDA runtime: 12.6
GPU: NVIDIA GeForce GTX 1070
Compute capability: 6.1
Wheel cubins: sm_50, sm_60, sm_70, sm_75, sm_80, sm_86, sm_90
Synchronized 2x2 CUDA matrix result: 8.0
ACE-Step import: passed
Source plus environment size: 6.8 GiB
Models downloaded: no
```

The first probe rejected the wheel because it demanded the exact label
`sm_61`. Inspection showed that the wheel exposes `sm_60`, and the real CUDA
operation had already succeeded. The corrected gate follows NVIDIA's cubin
rule: a target with the same major and a lower-or-equal minor capability runs
on the higher-minor desktop GPU. It now requires both that compatible target
and synchronized real computation, rather than trusting labels alone.

The pinned checkout remains at the exact upstream commit with three intentional
working-tree overlay files. Their combined diff SHA-256 is
`d0bbcd14527026f5225bb65aad0f242ec27600cdec766a5b4af244fffb69f576`:

```text
acestep/core/generation/handler/init_service_downloads.py
acestep/core/generation/handler/init_service_orchestrator.py
profile_inference.py
```

After a separate owner approval, the model-download gate completed with this
receipt:

```text
DiT checkpoint: acestep-v15-turbo
LM checkpoint: acestep-5Hz-lm-0.6B
Files verified: 25
Bytes verified: 7,709,375,886
Checkpoint disk footprint: 7.2 GiB
Partial files remaining: 0
```

## Thirty-second pilot result

The first invocation exposed an upstream false-success boundary: generation
returned a failed result with 48,000 NaN float16 latents, but the profiler
exited zero. It also entered its automatic downloader because its "main model"
presence check expects the intentionally omitted bundled 1.7B LM. Offline mode
prevented network access, but Soul now bypasses that path entirely.

The release's error message recommends `ACESTEP_DTYPE=float32`, but v0.1.8 does
not implement the variable. The exact overlay added that missing behavior. A
float32 retry generated audio successfully, then revealed that the profiler
deleted its own temporary output. The v2 overlay retains that directory only
when Soul sets the bounded run flag. The final retry passed:

```text
Lifecycle: blocked_for_human_review
Run: 20260717T105854Z-30s
Audio duration: 30.000 seconds
Format: FLAC, 48 kHz, stereo
File size: 6,365,664 bytes
Audio SHA-256: 0beb060a120a7873b80c5e659410d2759cccd200a26937ec4113b1031deca0b3
Mean volume: -15.5 dB
Maximum volume: -1.0 dB
Diffusion: 2.993 seconds / 8 steps
Measured offload: 21.506 seconds
Peak CUDA allocation reported by ACE-Step: 4.83 GiB
Automatic downloader entered: no
Generation failure/traceback: no
Checkpoint manifest intact after run: yes
AMD chat health after run: ok
Lingering Music process or CUDA allocation: none
```

The audio is mechanically valid and non-silent. Musical quality, usefulness,
and whether it justifies the 90-second gate remain human judgments.

The owner accepted the 30-second candidate as musically suitable to advance.

## Ninety-second pilot result

The approved 90-second gate used the same upstream example, fixed seed, pinned
models, float32 compatibility overlay, strict-offline boundary, and bounded
foreground lifecycle. It passed:

```text
Lifecycle: blocked_for_human_review
Run: 20260717T171608Z-90s
Audio duration: 90.000 seconds
Format: FLAC, 48 kHz, stereo
File size: 19,610,981 bytes
Audio SHA-256: 9e175cc39051307a6c429267e4175e67ee0dff496e3795b6a156760863c529b8
Mean volume: -15.9 dB
Maximum volume: -1.0 dB
Total measured wall time: 47.966 seconds
Diffusion: 8.293 seconds / 8 steps
VAE decode: 14.429 seconds
Measured offload: 23.084 seconds
Peak CUDA allocation reported by ACE-Step: 5.02 GiB
Automatic downloader entered: no
Generation failure/traceback: no
Checkpoint manifest intact after run: yes
AMD chat health after run: ok
Lingering Music process or CUDA allocation: none
```

The candidate is mechanically valid and non-silent. Human review must determine
whether its longer-form musical structure remains coherent enough to advance to
the final 180-second A1 gate.

The owner accepted the 90-second candidate as musically suitable to advance.

## One-hundred-eighty-second pilot result

The approved final A1 host gate used the same pinned, strict-offline foreground
configuration and completed successfully:

```text
Lifecycle: blocked_for_human_review
Run: 20260717T193944Z-180s
Audio duration: 180.000 seconds
Format: FLAC, 48 kHz, stereo
File size: 39,794,158 bytes
Audio SHA-256: 5d5c50cd3468b0b7f9503ca4d0592166d80a6de88716ddae14c6e90d9d56a6f4
Mean volume: -15.5 dB
Maximum volume: -1.0 dB
Total measured wall time: 73.167 seconds
Diffusion: 18.654 seconds / 8 steps
VAE decode: 27.587 seconds
Measured offload: 23.953 seconds
Peak CUDA allocation reported by ACE-Step: 5.55 GiB
Automatic downloader entered: no
Generation failure/traceback: no
Checkpoint manifest intact after run: yes
AMD chat health after run: ok
Lingering Music process or CUDA allocation: none
```

All mechanical A1 host gates have now passed. Full A1 remains
`blocked_for_human_review` until the owner evaluates the three-minute song's
coherence and usefulness.

The owner accepted the 180-second candidate and approved advancing beyond A1.

## Local LLM eval results

Not run. Dependency isolation, hashes, CUDA compatibility, reboot evidence,
confirmation gates, and process boundaries require deterministic and measured
host validation, not language-model judgment.

## Known weaknesses

- The approved environment and models are installed. The 6.8 GiB source and
  environment footprint includes upstream's broad inference/training/UI lock;
  the selected checkpoints add 7.2 GiB.
- The 30-second candidate uses the upstream example prompt and fixed seed. It
  validates feasibility, not Soul's future project prompt/lyrics workflow.
- Mechanical validity cannot establish quality for future prompts, genres, or
  project-specific lyrics; each generated candidate still needs human review.
- The CUDA 12.6 substitution passed the ACE-Step import, CUDA matrix probe, and
  30-, 90-, and 180-second generations on the GTX 1070.
- Upstream's non-PyTorch lock includes many training and UI dependencies that
  the CLI feasibility pilot does not need; minimizing that environment is
  deferred until feasibility is known.
- A failed installation can leave visible partial user-local files for review;
  it never starts a background cleanup or silently deletes a prior install.
- The upstream profiler retains candidates under the run directory but is not
  yet a Soul-native generation schema. That belongs to Music A2.
- A1 used one upstream example and fixed seed across duration gates. A2 must
  establish Soul-native project inputs and provenance before broader quality
  conclusions are possible.

## Memory keys added or used

None. Model configuration is local setup state; no skill-private memory store
was introduced.

## Task lifecycle states touched

- `complete`: preflight, successful setup, and verified download.
- `failed`: invalid manifest, dependency, download, digest, GPU, or generation.
- `canceled`: bounded generation timeout.
- `blocked_for_human_review`: setup/download preview and successful audio pilot.

Every operation is foreground and terminal. There is no service, listener,
watcher, scheduler, queue, or polling loop.

## Risk classification

- Preflight and reboot assessment: Class 1 read-only inspection.
- Versioned user-local environment and verified model files: Class 2 local
  writes after exact confirmation.
- Foreground GPU generation: Class 2 compute and artifact creation.

## Human review checklist

- [x] Confirm the 7.71 GB selected checkpoint download set.
- [x] Confirm CUDA 12.6 is the right explicit Pascal compatibility lane.
- [x] Confirm general Soul setup should continue when `uv` is absent.
- [x] Review the exact setup plan before installing the environment.
- [x] Review the separate download plan before retrieving weights.
- [x] Listen to and accept the 30-second audio candidate.
- [x] Listen to and accept the 90-second audio candidate.
- [x] Listen to and accept the 180-second audio candidate.
- [x] Approve full A1 and proceed to Music A2.
