# Multi-Model and Music Studio A0 Review

Status: candidate-complete; human review required

Date: 2026-07-17

## What was implemented

- Defined a host-specific model topology with AMD conversation, NVIDIA music or
  fallback, and CPU control/audio support.
- Selected ACE-Step 1.5 2B/turbo as the first measured foreground music pilot,
  DiffRhythm as the first full-song comparison, and documented why YuE,
  MusicGen, ACE-Step XL, and unsupported AMD ROCm are not first choices.
- Defined Music Studio as an iterative project surface with creative briefs,
  lyrics, lawful references, generated candidates, lineage, A/B review,
  repainting, stems, and export boundaries.
- Defined private ignored storage without adding a music-private memory store.
- Defined explicit cross-runtime leases, manual NVIDIA arbitration, terminal
  lifecycle, cancellation, partial-output quarantine, and human review.
- Split implementation into A1–A5 and prohibited a dashboard tab until the
  foreground runner and cancellation boundary exist.
- Corrected the roadmap to reflect that Self Augmentation A4–A5 were already
  implemented and pushed.

## Files changed

- docs/soul/MULTI_MODEL_MUSIC_STUDIO_A0_BRIEF.md
- docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md
- docs/assessments/MULTI_MODEL_MUSIC_STUDIO_A0_REVIEW.md
- docs/ROADMAP.md
- docs/MILESTONES.md
- docs/CURRENT_STATE.md
- scripts/verify-multi-model-music-studio-a0.rb

No runtime code, dashboard asset, environment file, service, model, or private
project state changed.

## Commands run

- Read-only nvidia-smi hardware query.
- Read-only vulkaninfo summary.
- Read-only package, CPU, and memory inventory.
- Primary-source web research listed in the architecture.
- ruby scripts/verify-multi-model-music-studio-a0.rb
- git diff --check

## Deterministic test results

The A0 verifier checks the exact host lanes, lead and comparison candidates,
Qwen/music exclusion, no-automatic-switch boundary, private project layout,
reference provenance classes, terminal lifecycle, cancellation, phased gates,
and the explicit no-install/no-listener scope.

Result: pass.

## Local LLM eval results

Not run. This slice makes no conversational, routing, prompt, model, or
generation implementation change. Vendor model output cannot validate hardware
fit, originality, rights, safety, or architecture approval.

## Known weaknesses

- ACE-Step low-VRAM and speed figures are vendor evidence, not GTX 1070 results.
- Compute capability 6.1 and current driver visibility do not prove the current
  PyTorch/ACE-Step combination will run correctly.
- A 2–3 minute song may fit only with CPU offload and may be too slow for useful
  iteration. A1 must measure it.
- The current sequential dashboard cannot truthfully offer progress and
  cancellation for a long generation. A3 needs a separately approved bounded
  task-channel design.
- Audio similarity and provenance records reduce risk but cannot certify
  originality, copyright status, permission, or release readiness.
- Music quality remains a human creative judgment.

## Memory keys added or used

None. Music projects are private task artifacts. Future stable preferences use
the shared Soul memory layer only through existing review controls.

## Task lifecycle states touched

This documentation task terminates complete. The future runner is required to
terminate complete, failed, awaiting_input, canceled, or
blocked_for_human_review.

## Risk classification

Class 1 read-only host inspection and research plus Class 2 repository
documentation. No model process, external account, download, installation,
listener, persistent service, GPU mutation, or audio ingestion occurred.

## Human review checklist

- [ ] Confirm keeping chat on AMD while piloting music on NVIDIA is preferred.
- [ ] Confirm Qwen fallback and NVIDIA music must remain mutually exclusive.
- [ ] Confirm ACE-Step 1.5 is the right first feasibility pilot.
- [ ] Confirm named inspiration is distilled to musical attributes by default.
- [ ] Confirm reference audio requires explicit provenance/permission and later
      operation-specific briefs.
- [ ] Confirm A1 should remain CLI-only with no listener or service.
- [ ] Confirm 30-, 90-, and 150–180-second pilot gates are sufficient.
- [ ] Approve, request changes, or reject before any installation or download.
