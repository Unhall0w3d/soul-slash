# Conversational Soul Phase 13A Integrated Acceptance Review

## Implementation summary

Phase 13A adds a bounded integrated assessor over Soul's real in-process application facade, chat persistence, conversation runtime, orchestrator, host evidence, reviewed memory controls, artifact workflow, identity/style controls, and two-gate Skill Studio lifecycle. Twenty synthetic user exchanges and their twenty assistant responses are kept in a temporary root and discarded when the foreground assessment returns.

The assessor reports each of the ten scenarios in `docs/CONVERSATIONAL_SOUL_ACCEPTANCE.md`, returns `blocked_for_human_review` if any scenario fails, and remains explicitly subject to owner review even when all deterministic scenarios pass.

## Files changed

```text
bin/soul
lib/soul_core/app.rb
lib/soul_core/conversational_soul_acceptance_assessor.rb
scripts/verify-phase13a-integrated-acceptance.rb
docs/soul/PHASE13A_INTEGRATED_ACCEPTANCE_HARNESS_BRIEF.md
docs/soul/PHASE13B_LOCAL_MODEL_AND_DASHBOARD_ACCEPTANCE_BRIEF.md
docs/soul/PHASE13C_CONVERSATIONAL_SOUL_CLOSEOUT_BRIEF.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE13A_INTEGRATED_ACCEPTANCE.md
```

## Commands run

```text
ruby -c bin/soul
ruby -c lib/soul_core/app.rb
ruby -c lib/soul_core/conversational_soul_acceptance_assessor.rb
ruby bin/soul assess conversational-soul-acceptance --json
ruby scripts/verify-phase13a-integrated-acceptance.rb
```

## Deterministic test results

The integrated assessment passes all ten contract scenarios. It records twenty user exchanges, twenty assistant responses, bounded local fixture-provider calls, grounded host evidence, artifact preview and confirmed creation behavior, reviewed memory promotion, unrelated-skill avoidance, safe provider failure, identity/style stability, and wrong-confirmation rejection before exact Beta production promotion.

The focused verifier also runs Phase 12B, conversational-orchestrator, and Phase 12D.5 regressions.

## Local LLM eval results

Not part of Phase 13A. Phase 13B performs the separately bounded behavioral evaluation. Deterministic fixture responses in this slice validate routing and state composition, not prose quality.

## Memory keys

Reads: temporary Phase 13 fixture project memory only.

Writes/updates: one temporary candidate and approved project-memory event under the assessment root.

Forget behavior: the entire temporary assessment root is removed on return. No live shared memory is read or written.

## Lifecycle states touched

```text
complete
failed
awaiting_input
blocked_for_human_review
```

## Risk classification

Class 1 read-only repository assessment plus Class 2 temporary isolated writes. The production-promotion scenario mutates only a disposable fixture registry and never the repository or live Soul runtime.

## Safety and persistence check

No service, daemon, watcher, scheduler, background loop, polling primitive, cloud call, live production skill, live proposal, private chat, or private memory is added or used.

## Known weaknesses

- Deterministic provider responses validate integration, not conversational quality.
- The dashboard is not browser-driven in Phase 13A.
- Host evidence retains platform variability but is validated by the existing bounded assessor.

## Human review checklist

- [ ] All ten scenarios correspond to the acceptance contract.
- [ ] Twenty exchanges use one persistent chat through the application API.
- [ ] Test state is isolated and removed.
- [ ] Model fixture output is not used as safety approval.
- [ ] Confirmation gates remain exact and stale-state-bound.
- [ ] Failure behavior is explicit and bounded.
- [ ] Phase 13A is accepted.

## Human review outcome

Approved as part of the final Phase 13 review on 2026-07-15.
