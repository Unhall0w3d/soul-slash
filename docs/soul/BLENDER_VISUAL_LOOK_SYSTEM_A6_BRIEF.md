# Blender Visual Look System A6 Brief

Status: human-authorized implementation candidate; visual promotion remains pending review.

## Purpose

The A1–A5 Blender lane proved its complete technical lifecycle, but the first
production candidate also exposed the creative ceiling of clean primitives,
flat materials, basic lighting, and coarse audio pulses. A6 increases visual
fidelity without turning Blender into an arbitrary code or asset execution
surface.

## Approved slice

- Add a closed `look` map to the scene manifest with enum-only surface,
  atmosphere, camera, glow, and color-grade profiles.
- Implement every profile inside the repository-owned Blender adapter. The
  manifest may select a reviewed preset; it may not supply node graphs, Python,
  paths, drivers, add-ons, or imported assets.
- Preserve compatibility with retained A1 scenes and fail closed on unknown
  profiles or keys.
- Expose one explicit Look profile selector in Visual Studio and bind its exact
  value into preview, confirmation digest, candidate receipt, revision, and
  publication lineage.
- Add two denser reviewed scene families, `void_sanctuary` and `signal_forge`.
- Render one whole-bar production candidate for human aesthetic review.

## Bounded behavior

Execution remains one foreground Blender job under the existing AMD creative
lease, fixed frame budget, timeout, cancellation, retained-frame resume, and
human review gate. A6 adds no listener, daemon, scheduler, automatic retry,
external publication, or unattended Core transition.

## Acceptance

The review candidate must show a material improvement in depth, surface detail,
atmosphere, lighting, and composition over the accepted bioluminescent-grove
baseline. Technical success alone does not approve its aesthetic or promotion.
