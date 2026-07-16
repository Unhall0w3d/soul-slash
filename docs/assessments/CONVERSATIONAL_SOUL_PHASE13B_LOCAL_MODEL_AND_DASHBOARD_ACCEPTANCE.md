# Conversational Soul Phase 13B Local Model and Dashboard Acceptance Review

## Implementation summary

Phase 13B adds a bounded, foreground-only, synthetic twenty-turn local-model evaluator and deterministic dashboard structural verification. The evaluator uses the configured local provider through the real conversation runtime in a temporary root. It retains response hashes and bounded observations, not the transcript or endpoint.

## Files changed

```text
scripts/run-phase13b-local-model-acceptance.rb
scripts/verify-phase13b-local-model-dashboard-acceptance.rb
docs/assessments/CONVERSATIONAL_SOUL_PHASE13B_LOCAL_MODEL_AND_DASHBOARD_ACCEPTANCE.md
```

## Commands run

```text
ruby scripts/run-phase13b-local-model-acceptance.rb
ruby scripts/verify-phase13b-local-model-dashboard-acceptance.rb
```

## Deterministic test results

The Phase 13B verifier confirms the evaluator's explicit turn and timeout bounds, local-only provider restriction, absence of transcript writes, hash-only response evidence, three primary dashboard tabs, Review Center and authentication surfaces, initial/manual system-status behavior, and absence of timer, WebSocket, or event-stream polling primitives.

## Local LLM eval results

The first bounded run completed 20/20 turns in 209.2 seconds but correctly returned `blocked_for_human_review`: 9 turns produced model content, 10 safely fell back after the provider returned empty content, and one prompt legitimately selected a read-only skill because it named host/filesystem inspection. Four of six continuity probes passed, all responses were nonempty, and no cloud fallback occurred. The evaluator had imposed a 256-token output cap, which was below Soul's normal 1,024-token conversation cap and insufficient for this thinking-capable model on several turns. The probe language and artificial cap were corrected before the candidate run; the safety fallback itself required no weakening.

The corrected candidate run used the normal 1,024-token conversation cap with the configured local `soul-qwen3-8b-q4` model. It completed 20/20 turns through the model path in 265.5 seconds. All responses were nonempty, 6/6 continuity probes passed, all 20 response hashes were unique, and observed per-turn latency ranged from approximately 4.7 to 21.3 seconds. No cloud fallback occurred, no transcript was retained, and model output granted no approval.

```text
turns completed: 20/20
model turns: 20/20
continuity probes: 6/6
unique response hashes: 20/20
transcript retained: no
cloud fallback: no
```

## Memory keys

No live memory is read or written. The synthetic conversation uses a temporary chat/runtime root that is removed when the evaluator returns.

## Lifecycle states touched

```text
complete
failed
blocked_for_human_review
```

## Risk classification

Class 1 local-only behavioral evaluation. The local provider receives synthetic public test prompts only.

## Safety and persistence check

No service, daemon, watcher, scheduler, polling loop, cloud fallback, transcript persistence, credential output, endpoint output, dashboard mutation, or approval mutation is added.

## Known weaknesses

- Heuristic continuity checks cannot substitute for human judgment of conversational quality.
- Static dashboard checks cannot substitute for the owner's visual/product review.
- Model behavior may vary between runtime/model revisions.

## Human review checklist

- [ ] Twenty bounded local-model turns completed.
- [ ] Synthetic prompts contain no private content.
- [ ] No transcript, endpoint, or credential was committed.
- [ ] Continuity observations are useful and honestly reported.
- [ ] Dashboard tabs, Review Center, status behavior, and no-polling boundary remain intact.
- [ ] Owner accepts conversational and visual behavior.

## Human review outcome

Pending final Phase 13 review.
