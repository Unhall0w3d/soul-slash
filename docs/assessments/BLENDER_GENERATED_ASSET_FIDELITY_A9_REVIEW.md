# Blender generated-asset fidelity A9 — human review packet

## Candidate state

Deterministic trust-boundary implementation is candidate-complete. Private GPU
reconstruction and Blender comparison evidence remain pending. Every resulting
asset and visual treatment must end `blocked_for_human_review`; this packet is
not aesthetic approval, production admission, binding, publication, or merge
authority.

## What was implemented

- a closed manifest for one immutable owner-private GLB beneath a configured
  private generated-asset root;
- exact schema, identifier, relative-path, byte-count, SHA-256, profile, and
  containment validation before Blender can import an asset;
- closed 720p and 1080p twelve-second study profiles;
- closed `res_1024`, `res_1536_geometry`, and `res_1536_textured`
  reconstruction labels, with `res_2048` explicitly rejected;
- five separate candidate material roles retaining the verified source
  texture and declaring spatial-mask uncertainty;
- deterministic layered stars, four fixed lights, AgX grading, compositor
  glow, four review angles, and a 360-degree orbit without a rendered duplicate
  endpoint frame; and
- bounded EEVEE preview plus 64- and 128-sample Cycles probe profiles that fail
  closed unless the exact runtime exposes an enabled AMD HIP device.

The implementation does not generate candidates, choose a winner, browse for
assets, accept arbitrary scene instructions, or confer publication authority.

## Files changed

- `scripts/blender/soul_generated_asset_manifest.py`
- `scripts/blender/soul_generated_asset_study.py`
- `scripts/verify-blender-generated-asset-fidelity-a9.py`
- `docs/soul/BLENDER_GENERATED_ASSET_FIDELITY_A9_BRIEF.md`
- `docs/assessments/BLENDER_GENERATED_ASSET_FIDELITY_A9_REVIEW.md`

Private source imagery, manifests, GLBs, textures, `.blend` files, frames, and
comparison videos remain outside Git.

## Commands and deterministic results

The candidate is expected to pass:

- `python3 scripts/blender/soul_generated_asset_manifest.py --self-test`
- `python3 scripts/verify-blender-generated-asset-fidelity-a9.py`
- `python3 -m py_compile scripts/blender/soul_generated_asset_manifest.py scripts/blender/soul_generated_asset_study.py scripts/verify-blender-generated-asset-fidelity-a9.py`
- existing Blender A1–A8 deterministic regression commands;
- JSON validation for any private study manifest used during qualification; and
- `git diff --check`.

The A9 verifier uses temporary synthetic fixtures only. It exercises manifest
and asset containment, symlink rejection, byte and digest checks, size bounds,
closed profiles, explicit `res_2048` rejection, safe receipt redaction, scene
limits, lifecycle termination, deterministic orbit construction, and Cycles
fail-closed behavior without reading a private asset or invoking Blender/GPU
work.

## Live qualification evidence

Five fixed-seed res-1024 reconstructions completed on the AMD Radeon RX 6900 XT
with GPU-required execution and a 2048-pixel generated atlas. The original seed
`481516` completed previously in 207.4 seconds. The four additional candidates
completed as follows:

| Seed | Elapsed | GLB bytes | Faces | Welded non-manifold edges |
| --- | ---: | ---: | ---: | ---: |
| `1337` | 137.5 s | 14,958,636 | 278,648 | 7,388 |
| `314159` | 140.5 s | 15,780,100 | 281,954 | 6,771 |
| `424242` | 136.1 s | 16,221,440 | 294,582 | 6,638 |
| `8675309` | 107.4 s | 14,492,360 | 282,054 | 5,635 |

All five remain single-material, non-watertight generated meshes. Machine
topology favors seed `8675309`; four-angle visual review favors seed `1337` as
the candidate with the clearest overall figure and wing silhouette. Neither
measurement selects or promotes a winner.
The pipeline does not select a winner.

The bounded res-1536 geometry-only probe used seed `481516`. It reached the full
1536 grid with 24,604 high-resolution tokens and completed the 278-second
high-resolution flow without NaN or fallback. Shape decode then requested a
15,654.70 MiB device allocation and failed out-of-memory on the 16 GiB GPU. Per
the brief, the 1536 branch stopped after this first failure; no retry and no
textured 1536 candidate ran.

The seed-1337 review candidate passed exact manifest validation and a Blender
5.2 background dry run. The corrected 1080p EEVEE study produced a `.blend`
file and four fixed-angle stills with normalized 4.8-unit height, 70 mm camera,
targeted lighting, distinct spatial candidate materials, 420 deterministic
stars, a true-black node-based world, AgX grading, and compositor glow. The
output remains owner-private and `blocked_for_human_review`.

Cycles/HIP remains unavailable in the exact reviewed Blender background
runtime, so no Cycles probe ran and no installation or runtime substitution was
attempted.

## Local LLM evaluation

Not applicable. No model output decides asset containment, profile admission,
renderer capability, lifecycle state, winner selection, aesthetic quality, or
publication eligibility.

## Memory and lifecycle

- shared Soul memory keys added or changed: none;
- lifecycle states touched by the adapter: `blocked_for_human_review` on a
  valid bounded study and `failed` on rejected validation or unavailable
  renderer capability;
- private absolute and relative asset paths are omitted from the public
  receipt; and
- no service, daemon, listener, watcher, scheduled task, automatic retry,
  background continuation, or skill-private memory was added.

## Risk classification

Moderate owner-local creative-compute and private-artifact risk. The manifest
is private-root contained and exact-digest bound; Blender receives only the
verified process-local GLB path and repository-owned presets. Cycles cannot run
without reviewed HIP capability. GPU expenditure and visual quality still
require explicit foreground execution and human review.

## Known weaknesses

- One source view cannot establish true side or rear anatomy; higher geometry
  resolution cannot repair information absent from the source.
- Spatial material masks are deterministic guesses, not semantic segmentation.
  They may misclassify hands, wings, hair, cloth, or boots.
- Smooth shading and distinct material response do not retopologize, rig,
  repair non-manifold geometry, or generate normal/displacement detail.
- The closed star, light, glow, and orbit treatments establish a repeatable
  comparison, not final art direction.
- A valid HIP inventory does not prove temporal denoising quality, stable
  feathers, acceptable render time, or available memory. Those require the
  bounded live probe.
- Res-1536 shape decode exceeds the current 16 GiB device-memory boundary for
  this subject and runtime even though its high-resolution flow completes.
- A few close hero stars still expose faceted source geometry; they are review
  evidence, not a promoted production star treatment.
- The adapter exposes a static reconstruction study only; it does not make a
  generated character a production Visual Studio asset.

## Human review checklist

- [ ] Review all fixed-seed 1024 four-angle contact sheets without automatic
  winner selection.
- [ ] Choose whether any 1024 candidate is suitable as the retained source.
- [ ] Compare geometry-only 1536 evidence with the retained 1024 source and
  decide whether a textured 1536 run is justified.
- [ ] Inspect spatial material masks at all four angles for skin, hair, wings,
  cloth, and boots.
- [ ] Compare baseline and polished EEVEE treatments at identical framing.
- [ ] If HIP is available, compare 64- and 128-sample Cycles stills and the
  bounded two-second temporal sample for cost, noise, denoising, and shimmer.
- [ ] Inspect the exact loop boundary and confirm no duplicated endpoint frame.
- [ ] Confirm private imagery and generated artifacts remain outside Git.
- [ ] Approve, request revision, or reject A9 visual evidence.
- [ ] Separately decide whether a later production generated-asset intake slice
  should be proposed.
