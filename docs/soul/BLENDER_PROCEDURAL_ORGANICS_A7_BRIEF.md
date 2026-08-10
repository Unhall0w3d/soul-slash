# Blender Procedural Organics A7 Brief

Status: human-authorized implementation candidate; visual promotion remains
pending review.

## Purpose

A6 proved that trusted surface, atmosphere, depth, glow, and grading profiles
materially improve finish. Its live candidate also showed that materials cannot
hide primitive geometry: the grove trees remain cylinders with coarse crowns,
and mushrooms remain flattened spheres on cylinders. A7 adds a small closed
organic-construction vocabulary owned entirely by Soul's trusted Blender
adapter.

## Approved slice

- Add an optional closed `organics` collection to the retained scene manifest.
  Existing manifests receive an empty collection during normalization.
- Support exactly two first archetypes:
  - `willow_tree`: tapered trunk and visible roots, hierarchical curved
    branches, drooping willow strands, combined leaf geometry, deterministic
    asymmetry, and a seamless bounded sway preset.
  - `mushroom_cluster`: tapered and curved stems, revolved cap profiles,
    overhangs, radial underside gills, deterministic scale and tilt variation,
    and bounded cluster counts.
- Every entry carries an ID, archetype, transform, deterministic seed, exact
  reviewed material roles, and an archetype-specific closed parameter map.
- Implement all curves, vertices, faces, modifiers, and animation inside the
  repository-owned adapter. The manifest cannot supply Blender code, arbitrary
  node graphs, paths, imported geometry, drivers, add-ons, or unbounded counts.
- Add one reviewed `willow_fungal_grove` family and expose it in Visual Studio.
- Render one exact whole-bar candidate through the existing preview, execution,
  AMD lease, review, revision, binding, and publication lifecycle.

## Closed ranges

The validator and adapter must agree on exact keys and bounds. Willow branch
depth is limited to `2..4`; primary branches to `4..10`; hanging strands to
`3..9` per primary branch; leaves to a fixed maximum enforced by those bounds.
Mushroom count is limited to `3..12`, cap profiles are reviewed enums, gill
segments are bounded, and generated mesh totals must remain within the existing
foreground timeout and frame budget.

## Bounded behavior

Execution remains one foreground Blender job under the existing exclusive AMD
creative lease, fixed frame count, 30-minute timeout, explicit cancellation,
retained partial-frame resume, and human review gate. A7 adds no service,
listener, scheduler, watcher, automatic retry, external publication, or
unattended Core transition.

## Acceptance

- Old A1–A6 manifests normalize with `organics: []` and retain stable safety
  behavior.
- Unknown archetypes, keys, material roles, parameter names, enums, and
  out-of-range counts fail closed in both Ruby and Python validation.
- The generated willow reads as a branching, drooping tree rather than stacked
  primitives.
- Mushrooms show curved/tapered stems, profiled caps, and visible underside
  structure rather than sphere-on-cylinder silhouettes.
- The whole-bar candidate remains editable as `.blend`, loop-safe, private,
  digest-bound, and `blocked_for_human_review`.
