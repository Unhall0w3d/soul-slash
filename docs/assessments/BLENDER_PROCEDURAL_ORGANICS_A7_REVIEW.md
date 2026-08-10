# Blender Procedural Organics A7 Candidate Review

## Candidate status

`candidate_complete` pending Operator visual review. A7 extends the accepted
Blender lane with two trusted procedural archetypes; it does not change the
existing human review, binding, deletion, or publication gates.

## What was implemented

- An optional closed `organics` manifest collection that defaults to an empty
  list for every retained A1-A6 scene.
- A deterministic `willow_tree` builder with tapered root flare and trunk,
  continuous curved primary limbs, bounded secondary forks, distributed
  drooping strands, crossed tapered leaf blades, and seamless restrained sway.
- A deterministic `mushroom_cluster` builder with curved tapered stems,
  revolved bell, convex, conical, or flat cap profiles, visible overhangs, and
  radial underside gills.
- Exact archetype-specific material roles, parameter maps, enum values, count
  limits, and numeric ranges in both Ruby and Python validation boundaries.
- A Willow fungal grove template and Visual Studio selector that use the new
  builders instead of the old trunk, crown, stem, and cap primitive assemblies.
- Deterministic rejection coverage for unknown keys, archetypes, roles,
  parameters, enum values, and out-of-range complexity controls.

## Files changed

The slice touches the Blender manifest, service catalog, trusted adapter,
reviewed scene templates, Visual Studio selector, A1-A7 deterministic
verifiers, operator guide, roadmap, project timeline seed, and this review
packet.

## Commands run

```text
make verify-blender-scene-a1-a7
ruby scripts/verify-music-visual-companion.rb
ruby scripts/verify-music-publication-package.rb
node --check assets/dashboard/dashboard.js
python3 -m py_compile scripts/blender/soul_scene_adapter.py
git diff --check
```

All checks passed. Blender 5.2 LTS also constructed the template directly and
saved both `.blend` and still artifacts before the normal Soul production flow
was exercised.

## Live production evidence

The exact kept Glassroot Signal audio produced this normal Visual Studio
candidate through preview, exact confirmation, AMD lease, 384-frame EEVEE
render, encode, and human-review handoff:

```text
Scene: blender_scene_d86c38c5c2589779
Template: willow_fungal_grove
Look: cinematic_organic
Resolution: 1280x720
Frame rate: 30 fps
Musical span: 8 bars at 150 BPM in 4/4
Frames: 384/384
Duration: 12.8 seconds
Loop boundary: matched
Artifacts: scene.json, scene.blend, still.png, audio-analysis.json, preview.mp4
Lifecycle: blocked_for_human_review
```

The generated tree now reads as a rooted weeping form with a branching crown
and hanging foliage rather than a cylinder under coarse spheres. The fungi use
distinct curved stems and modeled caps with underside gills rather than spheres
placed on cylinders. Opening and midpoint inspection confirmed that the light
response changes while the subject geometry remains coherent.

## Local model and delegated evaluation

No LLM output was used for safety, schema acceptance, execution authority,
lineage, or approval. A bounded Terra implementation worker owned only the
manifest validator, trusted Blender adapter, and A7 verifier. It returned exact
changed paths and passing command evidence. The primary agent independently
reviewed the closed capability boundary, refined the visible branch and foliage
construction, ran the integration suite, and qualified the result through the
real host-GPU Visual Studio flow.

## Known weaknesses

- These are stylized procedural forms, not photoreal scanned botany. The willow
  deliberately favors a graphic silhouette suitable for Soul's visual language.
- Leaf blades share a combined low-complexity mesh; they are not individually
  simulated, textured, or collision-aware.
- Mushroom caps and gills have modeled profiles but no imported displacement or
  photogrammetry textures.
- Only the first two reviewed archetypes are accepted. Free-form geometry,
  arbitrary Python, Geometry Nodes supplied by a model, external asset paths,
  add-ons, and downloaded models remain prohibited.
- EEVEE is qualified; Cycles and Blender 6 remain unqualified.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Lifecycle states touched: `complete`, `failed`, `awaiting_input`, and
  `blocked_for_human_review`.
- No new service, listener, scheduler, watcher, automatic retry, or background
  process was added.

## Risk classification

Medium owner-local compute and owner-local Visual Studio state. Runtime remains
bounded by the existing Blender timeout and exclusive AMD creative lease. The
manifest cannot provide code, arbitrary paths, node graphs, drivers, add-ons,
network behavior, or publication authority.

## Human review checklist

- [ ] Willow silhouette reads as branching, rooted, and weeping rather than stacked primitives
- [ ] Hanging foliage is visible without overpowering the dark composition
- [ ] Mushroom stems and cap profiles show useful variation
- [ ] Cap overhang and underside gills improve the close visual read
- [ ] Audio response remains coherent and the whole-bar seam is acceptable
- [ ] Render time is acceptable for the additional geometry
- [ ] Editable `.blend`, preview, review, revision, binding, and publication paths remain usable
- [ ] A7 may be promoted only after this review
