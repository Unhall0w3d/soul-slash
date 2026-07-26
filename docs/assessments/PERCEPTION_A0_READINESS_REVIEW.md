# Perception A0 Readiness Review

## Candidate outcome

Perception A0 establishes that the host is ready for a bounded picture-
understanding Beta without a new model download.

The exact production Gemma 4 12B manifest includes a 175,115,584-byte BF16
multimodal projector. Hyprland capture, region selection, and deterministic OCR
prerequisites are installed. The current missing components are application
contracts and workflow code, not basic hardware or model availability.

The recommended next slice is A1 picture understanding using the existing Daily
Core model. Screen capture remains A2.

## Files changed

- `lib/soul_core/perception_readiness_assessor.rb`
- `scripts/soul-perception-readiness`
- `scripts/verify-perception-a0.rb`
- `lib/soul_core/capability_matrix.rb`
- `lib/soul_core/model_runtime_assessor.rb`
- `docs/soul/PERCEPTION_A0_READINESS_AND_ARCHITECTURE_BRIEF.md`
- `docs/assessments/PERCEPTION_A0_READINESS_REVIEW.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`

## Commands and results

- `ruby scripts/verify-perception-a0.rb` - PASS
- `scripts/soul-perception-readiness` - COMPLETE; no missing prerequisites
- `ruby scripts/verify-model-runtime-assessment-phase12.rb` - PASS
- `git diff --check` - PASS

## Deterministic coverage

- read-only/no-capture contract;
- projector discovery;
- current Core disclosure;
- capture and OCR prerequisite detection;
- untrusted-image/no-mutation policy;
- missing-projector behavior;
- no discovered executable is invoked.

## Local model evals

None. A0 does not send an image or prompt to a model. A1 will use a reviewed,
fixed image corpus and record measured results.

## Known weaknesses

- A manifest proves model packaging, not visual quality.
- No image has yet passed through Soul's provider abstraction.
- Current conversation messages accept string content only.
- Music and AMD-Free Core require an explicit Daily Core transition for the
  first proposed implementation.
- Screen capture accuracy and privacy behavior are design-only until A2.

## Memory and lifecycle

- Memory keys added or used: none.
- Images captured: none.
- Durable private state created: none.
- Lifecycle touched: one bounded read-only `complete` assessment.

## Risk

Class 1 read-only assessment. The planned A1 feature is local-private and
read-only with potentially sensitive input. A2 screen capture is a separate,
higher-privacy gate.

## Human review checklist

- [ ] Accept the existing Gemma 4 12B model as the A1 lead.
- [ ] Accept Qwen3-VL 8B and MiniCPM-V 4.5 only as conditional challengers.
- [ ] Accept Daily Core as the initial required Core.
- [ ] Accept ephemeral image retention as the default.
- [ ] Confirm image content is evidence and never authorization.
- [ ] Confirm A1 supports attachments only and does not capture the screen.
- [ ] Confirm A2 screen capture requires a later explicit gate.
