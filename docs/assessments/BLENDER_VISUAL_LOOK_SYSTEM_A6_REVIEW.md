# Blender Visual Look System A6 Candidate Review

## Candidate status

`candidate_complete` pending Operator visual review. A6 expands the accepted
A1–A5 Blender lane; it does not alter the human review, binding, deletion, or
publication gates.

## What was implemented

- A closed `look` manifest map with enum-only surface, atmosphere, camera,
  glow, and color-grade values.
- Five reviewed Dashboard look bundles: template treatment, cinematic organic,
  liminal haze, signal forge, and crystalline void.
- Trusted adapter-owned procedural surface detail, bounded world atmosphere,
  depth of field, compositor glow, and AgX grading.
- Two denser reviewed scene families: Void Sanctuary and Signal Forge.
- Look selection in the exact preview digest, execution scope, candidate
  receipt, immutable revision lineage, and Visual Studio controls.
- Safe clean defaults for retained A1 manifests and deterministic rejection of
  unknown look keys or values.

## Files changed

The slice touches the Blender manifest, service, adapter, closed application
contract, Visual Studio control surface, reviewed template catalog,
deterministic verifiers, operator documentation, roadmap, and project timeline
seed.

## Commands run

```text
make verify-blender-scene-a1-a6
ruby scripts/verify-music-visual-companion.rb
ruby scripts/verify-music-publication-package.rb
node --check assets/dashboard/dashboard.js
python -m py_compile scripts/blender/soul_scene_adapter.py
git diff --check
```

All deterministic checks passed. Direct Blender 5.2 still renders also passed
for both new scene families. The sandboxed one-frame benchmark fell back to CPU
because Vulkan initialization was unavailable and took approximately 24
seconds; the same retained frame through the host GPU path took approximately
1.38 seconds. Production qualification must therefore use Soul's normal host
runtime, not a filesystem sandbox that masks the AMD device.

## Live production evidence

The exact kept Glassroot Signal audio produced this normal Visual Studio
candidate through preview, exact confirmation, AMD lease, render, encode, and
human-review handoff:

```text
Scene: blender_scene_370d86fc604c1ba2
Template: void_sanctuary
Look: crystalline_void
Resolution: 1280x720
Frame rate: 30 fps
Musical span: 8 bars at 150 BPM in 4/4
Frames: 384/384
Duration: 12.8 seconds
Loop boundary: matched
Artifacts: scene.json, scene.blend, still.png, audio-analysis.json, preview.mp4
Lifecycle: blocked_for_human_review
```

The path is production-viable and the material, reflection, atmosphere, glow,
and depth treatment are visibly stronger than the A1 primitive baseline. The
candidate also reveals the remaining ceiling honestly: Void Sanctuary still
inherits too much of the bioluminescent-grove composition to read as a distinct
monumental sanctuary. It is useful qualification evidence for the look system,
not evidence that the composition vocabulary is finished.

## Local LLM evaluation

Not used for safety, execution, schema, lineage, or approval. Spark performed a
bounded read-only map of the current visual ceiling and drafted part of the
closed adapter implementation; the primary agent reviewed, repaired, and
validated the resulting code and live Blender behavior.

## Known weaknesses

- The new scene families currently extend accepted procedural compositions;
  they do not yet provide arbitrary bespoke meshes, reviewed texture packs,
  characters, rigs, simulations, or imported assets.
- Void Sanctuary needs a later composition-director slice with staged plinths,
  arches, rings, spires, suspended focal structures, and shot-level controls;
  the current candidate should not be promoted on its name alone.
- Surface, atmosphere, and post-processing presets materially improve depth and
  finish, but they do not make free-form creative-direction prose rewrite scene
  geometry.
- EEVEE is qualified; Cycles remains inventoried but unqualified.
- Blender 5.2 emits node-enable deprecation warnings for Blender 6. The pinned
  runtime must not be upgraded without adapter qualification.
- Richer volume and glow effects make CPU fallback impractical for full loops;
  Soul's AMD resource lease and host GPU evidence remain required.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Lifecycle states touched: `complete`, `failed`, `awaiting_input`, `canceled`,
  and `blocked_for_human_review`.
- No new service, listener, scheduler, watcher, automatic retry, or background
  process was added.

## Risk classification

Medium owner-local compute and owner-local Visual Studio state. Execution stays
bounded by the existing Blender timeout and exclusive AMD creative lease. The
manifest cannot provide Python, paths, node graphs, add-ons, drivers, or
external publication authority.

## Human review checklist

- [ ] Look selection is clear and produces an obvious visual difference
- [ ] Void Sanctuary is materially richer than the accepted primitive baseline
- [ ] Depth of field retains a readable focal subject rather than excessive blur
- [ ] Atmosphere and glow add depth without obscuring scene geometry
- [ ] Audio response remains coherent and the whole-bar seam is acceptable
- [ ] The render duration is acceptable for the fidelity gained
- [ ] The editable `.blend`, private preview, review, revision, binding, and publication paths remain usable
- [ ] A6 may be promoted only after this review
