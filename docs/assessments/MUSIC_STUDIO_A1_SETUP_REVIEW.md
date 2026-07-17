# Music Studio A1 Setup Boundary Review

Status: candidate-complete; human review required

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

## Local LLM eval results

Not run. Dependency isolation, hashes, CUDA compatibility, reboot evidence,
confirmation gates, and process boundaries require deterministic and measured
host validation, not language-model judgment.

## Known weaknesses

- No model files have been downloaded. The approved environment is installed;
  its 6.8 GiB footprint includes upstream's broad inference/training/UI lock.
- The CUDA 12.6 substitution is supported by PyTorch's Pascal matrix but still
  needs the real ACE-Step import and generation pilots.
- Upstream's non-PyTorch lock includes many training and UI dependencies that
  the CLI feasibility pilot does not need; minimizing that environment is
  deferred until feasibility is known.
- A failed installation can leave visible partial user-local files for review;
  it never starts a background cleanup or silently deletes a prior install.
- The upstream profiler retains candidates under the run directory but is not
  yet a Soul-native generation schema. That belongs to Music A2.
- Full Music A1 remains incomplete until the operator reviews measured GPU
  stability, AMD chat responsiveness, time, and audio output at all gates.

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

- [ ] Confirm the 7.71 GB selected checkpoint download set.
- [ ] Confirm CUDA 12.6 is the right explicit Pascal compatibility lane.
- [ ] Confirm general Soul setup should continue when `uv` is absent.
- [ ] Review the exact setup plan before installing the environment.
- [ ] Review the separate download plan before retrieving weights.
- [ ] Review 30-, 90-, and 180-second stability, timing, and audio candidates.
- [ ] Approve, revise, or reject full A1 before proceeding to Music A2.
