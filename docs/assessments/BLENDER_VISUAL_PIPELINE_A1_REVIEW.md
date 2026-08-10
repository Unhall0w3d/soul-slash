# Blender Visual Pipeline A1 Review Packet

## Candidate status

`candidate_complete` as part of the consolidated A1–A5 Operator review.

This document is the review artifact for A1 and intentionally does not grant production approval.

## Files changed

- `lib/soul_core/blender_scene_manifest.rb`
- `scripts/blender/soul_scene_adapter.py`
- `config/blender_scene_templates.json` (five reviewed template families)
- `scripts/verify-blender-scene-a1.rb`
- `docs/soul/BLENDER_VISUAL_PIPELINE_A1_BRIEF.md`
- `docs/assessments/BLENDER_VISUAL_PIPELINE_A1_REVIEW.md`

## Commands run

- `ruby -c lib/soul_core/blender_scene_manifest.rb`
- `python3 -m py_compile scripts/blender/soul_scene_adapter.py`
- `ruby -c scripts/verify-blender-scene-a1.rb`
- `ruby scripts/verify-blender-scene-a1.rb`

## Deterministic checks

The verifier script currently checks:

- valid template manifests are accepted
- unknown top-level keys are rejected
- nested forbidden keys are rejected
- unsafe output names are rejected
- audio-binding target IDs are validated
- canonical digest stability under reordering
- adapter token restrictions and required output behavior
- template catalog closure and exact-template coverage
- adapter Python syntax

## Human review notes

- strict key closure is present and deterministic
- manifest output fields are file names only; no paths are accepted
- adapter is repository-owned and constructs scene data-blocks only
- adapter includes a dry-run mode for structural validation without Blender runtime
- there are no new background services, daemons, listeners, watchers, or recurring loops

## Known risks

- adapter animation writes keyframes with simplified property mapping; high-complexity animation curves may require follow-up expansion in A2
- Blender 5.2 currently warns that `Material.use_nodes` and `World.use_nodes`
  are deprecated for Blender 6; the pinned 5.2 LTS adapter is valid, and a
  future version qualification must update those calls before changing the pin

## Live adapter evidence

The trusted adapter constructed and saved a real Blender 5.2 `.blend` plus
still before integration. The later production qualification then exercised
the same adapter through 389 verified 1920×1080 frames and MP4 encoding.
This is local runtime evidence, not CI emulation.

## Memory keys / lifecycle

- Memory reads/writes: none
- Lifecycle states in scope: `complete`, `failed`, `blocked_for_human_review`

## Risk classification

Medium local risk: deterministic scene construction logic writes `.blend` and still files and may include large generated payloads; all work remains bounded and operator-approved.

## Human review checklist

- [ ] Closed manifest schema rejects unknown keys exactly and predictably
- [ ] `schema_version` and section-specific constraints are correct
- [ ] No script/driver/import/add-on paths are accepted from manifest
- [ ] Canonical digest remains stable on reorder operations
- [ ] Adapter restrictions are visible in source and syntax is clean
- [ ] Template catalog contains only the intended five templates
- [ ] Verifier passes without exceptions
- [ ] Candidate remains within bounded scope and bounded foreground requirements
