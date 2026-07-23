# Visual Studio A3 Motion Qualification Review

## Candidate status

`candidate_complete` for tooling review; host install, model download, live pilot,
and production dashboard enablement remain human-gated.

## What was implemented

- Replaced the stale LTX 2B research placeholder with Wan 2.2 TI2V 5B Q4 as
  the measured first candidate.
- Added a separate pinned `stable-diffusion.cpp` Vulkan runtime and exact
  8,520,510,320-byte model manifest without changing the still-image runtime.
- Added check, setup plan/install, download plan/download, and image-guided
  pilot plan/run commands.
- Large model transfers use explicit 256 MiB HTTP byte ranges. Each temporary
  chunk must match the requested length before it is appended to a bounded,
  regular, non-symlink prefix. No partial file is promoted until its exact size
  and SHA-256 match the manifest.
- Bound the source still, prompts, seed, profile, runtime revision, and model
  hashes into the run approval digest.
- Added a bounded process group, interruption/timeout cleanup, `ffprobe`
  integrity checks, immutable run output, and a review receipt.
- Updated the dashboard’s unavailable-motion copy; no production action was
  enabled.

## Files changed

```text
Makefile
assets/dashboard/dashboard.js
assets/dashboard/index.html
config/visual_motion_models.json
config/visual_studio_models.json
docs/soul/VISUAL_STUDIO_A0_A1_BRIEF.md
docs/soul/VISUAL_STUDIO_A3_MOTION_QUALIFICATION_BRIEF.md
docs/assessments/VISUAL_STUDIO_A3_MOTION_QUALIFICATION_REVIEW.md
scripts/soul-visual-motion-runtime
scripts/verify-visual-motion-qualification.rb
scripts/verify-visual-studio-a1.rb
```

## Commands and deterministic results

```text
ruby -c scripts/soul-visual-motion-runtime — PASS
ruby -c scripts/verify-visual-motion-qualification.rb — PASS
ruby scripts/verify-visual-motion-qualification.rb — PASS (13 checks)
ruby scripts/verify-visual-studio-a1.rb — PASS (12 checks)
ruby scripts/verify-visual-studio-a2.rb — PASS (21 checks)
ruby scripts/verify-music-visual-companion.rb — PASS
node --check assets/dashboard/dashboard.js — PASS
JSON.parse config/visual_motion_models.json — PASS
JSON.parse config/visual_studio_models.json — PASS
make visual-motion-check — PASS; correctly reports runtime/models absent
git diff --check — PASS
```

The timeout fixture uses a ten-second child operation and a one-second ceiling.
The complete verifier returns in about two seconds, records terminal failure,
and confirms that no `.partial-*` run state remains.

## Local LLM eval

Not run. Model routing, prose behavior, and conversational intent are not part
of this qualification. An LLM cannot certify runtime pinning, process cleanup,
file integrity, or GPU compatibility.

## Memory keys

None added, read, or changed.

## Lifecycle states

`complete`, `failed`, `canceled`, `blocked_for_human_review`.

## Risk classification

Medium after execution: the approved install compiles a local Vulkan binary,
the approved download stores about 7.94 GiB outside Git, and the pilot applies a
bounded high-load GPU operation. This candidate performs none of those actions
until the exact human gates are invoked.

## Known weaknesses

- The host runtime build requires the distribution's Vulkan and SPIR-V
  development headers (`vulkan-headers` and `spirv-headers` on Arch) in addition
  to the Vulkan loader and shader tools. Setup now reports that dependency set
  explicitly before compiling.
- RX 6900 XT compatibility and peak memory are not yet proven.
- First live host evidence: Vulkan sampling completed 20/20 steps in 90.22
  seconds, but GPU VAE decode raised `vk::DeviceLostError`. The card recovered
  without a reboot and released model VRAM. A CPU VAE retry was safely canceled
  after roughly fourteen minutes with about 50 GiB RAM in use and no output yet.
  The qualification profile now pins the upstream-recommended Wan 2.2 TAEHV
  decoder; that revised path still requires a successful quality-reviewed pilot.
- The 8 fps pilot is a resource-oriented qualification profile, not the final
  delivery frame rate or quality target.
- Temporal quality, loopability, and subject stability require human review.
- Text-only video, longer clips, production Visual Studio candidates, motion
  review/disposition, song binding, and final mux/export remain later slices.

## Human review checklist

```text
[ ] Runtime/model selection and separate-root isolation are acceptable
[ ] Setup and download plans contain the expected exact identities
[ ] Live pilot completes and releases AMD resources
[ ] Video dimensions, duration, receipt, and hashes are correct
[ ] Motion is coherent enough to justify production integration
[ ] No dashboard motion control is enabled before that decision
```
