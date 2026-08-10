# Blender Visual Pipeline A0 Candidate Review

## Candidate status

`candidate_complete` pending Operator review of the technical preview and
receipt. This qualifies a bounded Blender runtime only; it does not expose a
Blender Scene lane in Visual Studio.

## What was implemented

- Pinned Blender 5.2.0 LTS and an EEVEE A0 profile.
- Added clean-startup and GPU capability evidence without changing Blender
  preferences.
- Added a repository-owned procedural copper/cyan fixture with visibly moving
  orbit markers.
- Bound the Blender binary, runtime, manifest, probe, and fixture digests into
  the exact approval plan.
- Acquired the existing exclusive `amd-vulkan-generation` lease for each run.
- Rendered two exact frame ranges, validated all frames, encoded an H.264
  preview, and retained an editable `.blend` plus immutable receipt.
- Removed partial state and released the lease on failure, cancellation, or
  timeout. No service, listener, scheduler, queue, or automatic retry was
  added.

## Live qualification evidence

```text
Profile: blender-5.2-lts-eevee-a0
Blender: 5.2.0 LTS
Renderer: BLENDER_EEVEE
GPU: AMD Radeon RX 6900 XT via Mesa OpenGL
Cycles inventory: RX 6900 XT HIP; GTX 1070 CUDA/OptiX; Ryzen 7 5800X CPU
Run: blender_a0_e8494a2b11282cf7
Elapsed: 4.863 seconds
Frames: 24/24 across 1..12 and 13..24
Preview: H.264, 640x360, 24 fps, 1.0 second
Lifecycle: blocked_for_human_review
AMD lease after completion: released
```

Artifacts remain owner-local:

```text
/home/bhones/.local/share/soul/blender-visual/runs/blender_a0_e8494a2b11282cf7/scene.blend
/home/bhones/.local/share/soul/blender-visual/runs/blender_a0_e8494a2b11282cf7/preview.mp4
/home/bhones/.local/share/soul/blender-visual/runs/blender_a0_e8494a2b11282cf7/receipt.json
```

## Artifact lineage

```text
Approved plan: e8494a2b11282cf7e75c700b6462d43fe4351d212942dd7d29f4b11459adbfb7
Runtime: 5a30aeea12c5f011740785718298a0ccb7393be982d3b92d4d3a43598b611f5d
Scene: 1fd205519ccbb9a2e58250d6a7036dfdd1ab5f26bba78d50348b5ec7bcce2fb9
Frames: 428447175dec4229bb8744935fd3be6e0cb5152e8807b3dce6d18c1c1e5edf41
Preview: 779f88db8beb1b8458fddc6218c6c42c5705cf5898dccb3d0eb5b2cf65981867
```

## Deterministic validation

```text
make verify-blender-visual-a0 — PASS (15 checks)
python -m py_compile scripts/blender/soul_runtime_probe.py scripts/blender/soul_a0_fixture.py — PASS
ruby -c scripts/soul-blender-visual-runtime — PASS
ruby -c scripts/verify-blender-visual-a0.rb — PASS
git diff --check — PASS
```

The verifier covers exact confirmation, stale-plan rejection inputs, runtime
and trusted-script lineage, split rendering, artifact validation, terminal
timeout behavior, partial cleanup, and lease release.

## Local LLM evaluation

Not run. A0 concerns executable identity, process bounds, GPU evidence,
filesystem containment, artifact validation, and approval lineage. Model output
cannot certify these properties.

## Memory and lifecycle

- Shared memory keys read or written: none.
- Lifecycle states touched: `complete`, `failed`, `canceled`, and
  `blocked_for_human_review`.

## Risk classification

Medium local compute and owner-local filesystem mutation. Blender and FFmpeg
run only as bounded foreground child process groups. No privileged operation,
network publication, persistent process, or arbitrary model-authored Python is
introduced.

## Known limits

- The preview is a technical motion fixture, not a production visual template.
- The A1 closed scene manifest and trusted adapter do not exist yet.
- Audio-reactive curves, seamless-loop review, Visual Studio lifecycle,
  Music Studio binding, and publication remain separately gated later phases.
- EEVEE qualified on the RX 6900 XT; Cycles devices were inventoried but Cycles
  rendering was not qualified.

## Human review checklist

```text
[ ] The one-second preview visibly demonstrates deterministic motion
[ ] The editable .blend opens safely with auto-execution disabled
[ ] The receipt and GPU evidence are sufficient for A0
[ ] The exact gate and absence of persistent/background behavior are acceptable
[ ] A1 closed scene-manifest work may proceed as a separate slice
```
