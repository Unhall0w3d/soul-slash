# Blender Visual Pipeline A1 — Closed Scene Manifest and Trusted Adapter

Status: Operator-authored implementation candidate

Date: 2026-08-10

## Scope

Implement A1 as a bounded manifest-anchored path from approved music-aware intent to deterministic scene construction.

Only these assets are in scope for this candidate:

- strict, closed JSON manifest schema in Ruby
- deterministic normalization + SHA-256 digest
- repository-owned Blender adapter for procedural construction via data blocks
- closed template catalog for initial visual families
- a deterministic verifier with fixture/structural coverage and adapter restriction checks

The runtime renderer and Visual Studio integration remain outside this slice.

## Accepted constraints carried into A1

- exact known keys only at every manifest level
- constrained IDs and frame ranges
- constrained palette, world, camera, lights, objects, materials, animation, audio-binding, and output
- no user-supplied paths in manifest payloads
- no scripts, drivers, add-ons, arbitrary node graphs, imports, network access, or auto-exec execution
- deterministic `.blend` + still generation path from manifest
- closed templates for `abstract`, `liminal`, `architectural`, `audio_reactive`

## Behavior

- `SoulCore::BlenderSceneManifest` validates manifest structure exactly and rejects unknown keys.
- `scripts/blender/soul_scene_adapter.py` consumes validated manifests and builds a bounded procedural scene.
- Adapter sets scene settings, object graph, materials, camera, lights, simple animation channels, and exports:
  - `<manifest>.blend` at supplied path
  - still PNG at supplied path
- Both `--dry-run` and live modes preserve manifest normalization and explicit restrictions.

## Canonicalization

- key order is normalized recursively
- known ordered lists are sorted by stable identifier
- animation tracks are sorted by target/property/frame
- normalized payload and SHA-256 are exposed as deterministic evidence

## Templates

`config/blender_scene_templates.json` contains closed entries for:

- `abstract`
- `liminal`
- `architectural`
- `audio_reactive`

Each template is a complete manifest with no mutable paths, no imported assets, and no unsafe keys.

## Acceptance checklist

- schema parse rejects unknown top-level keys
- schema parse rejects unknown nested keys
- schema parse rejects output filenames with directory traversal/separators
- schema parser rejects audio-binding unknown targets
- canonicalization digest remains stable when map/settable arrays are reordered
- adapter denies forbidden runtime capability patterns
- Python bytecode compile succeeds for adapter
- template catalog contains exactly the four required template entries
- verifier reports deterministic checks and no regressions

## Lifecycle

No new persistent process, service, or background loop is introduced.

## Human review

- validate outputs and risks in `docs/assessments/BLENDER_VISUAL_PIPELINE_A1_REVIEW.md`
