# Conversational Soul Phase 12D: Skill Studio Beta Lifecycle

## Candidate status

```text
status: candidate_complete_for_human_review
human_visual_review_required: yes
human_merge_review_required: yes
automatic_promotion: no
```

## What was implemented

- A bounded Skill Studio application service over existing local proposal packets.
- A canonical two-gate state record bound to proposal and Beta content digests.
- Gate 1 approval of an exact proposal revision for Beta implementation work.
- A Beta inventory separate from the production skill registry.
- Read-only projection of legacy alpha scaffolds as non-runnable migration candidates.
- A proposal-local Beta package contract with implemented-entrypoint and test-evidence requirements.
- Preview-first, exact-confirmation-only, foreground Beta execution.
- A maximum 60-second execution timeout, bounded arguments, bounded output, no retries, and one terminal result.
- Local bounded JSONL Beta diagnostics under `Soul/logs/beta_skills/`.
- Gate 2 approval of an exact tested Beta revision for a later promotion workflow.
- Dashboard inventories for proposals, Beta Skills, and registered production Skills.
- Proposal detail, cloud provenance, review checklist, Beta tests, weaknesses, run controls, and promotion blockers.

Gate 1 does not invoke Codex or generate implementation. Gate 2 does not promote, register, copy, merge, or release a skill.

## Files changed

```text
assets/brand/soul-slash-skill-studio.png
docs/soul/PHASE12D_SKILL_STUDIO_BETA_LIFECYCLE_BRIEF.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE12D_SKILL_STUDIO_BETA_LIFECYCLE.md
lib/soul_core/skill_studio_service.rb
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
assets/dashboard/index.html
assets/dashboard/dashboard.js
assets/dashboard/dashboard.css
scripts/verify-phase12d-skill-studio.rb
```

## Commands run

```text
node --check assets/dashboard/dashboard.js
ruby -c lib/soul_core/skill_studio_service.rb
ruby -c lib/soul_core/application_contract.rb
ruby -c lib/soul_core/application_facade.rb
ruby scripts/verify-phase12d-skill-studio.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
```

## Deterministic results

The focused Phase 12D verifier passed:

- proposal projection without silent rewrite;
- Gate 1 preview and exact confirmation;
- separate, implemented-only Beta inventory;
- exact-confirmation Beta invocation;
- foreground termination and diagnostic creation;
- current-revision test evidence for Gate 2;
- Gate 2 approval without promotion;
- invalidation after implementation change;
- application operation allowlisting;
- three dashboard inventories and two visible gates;
- safe DOM construction;
- absence of polling or background continuation.

The first Phase 12B regression attempt reached its repository-curation check and stopped because the new Phase 12D verifier had not yet been staged. This was expected candidate-work detection, not an application failure.

After intentional staging:

```text
Phase 12B in-process application API regression: PASS
Phase 12C foreground dashboard transport/security regression: PASS
staged and working-tree whitespace checks: PASS
```

The Phase 12C assessor was made phase-aware: it accepts its historical inert preview or the explicit two-gate Phase 12D surface. All listener, same-origin, CSRF, CSP, request-bound, foreground, no-polling, safe-DOM, and clean-termination checks remain enforced.

## Local LLM evals

Not run. This slice adds deterministic lifecycle, file-boundary, execution, and interface behavior. It does not add intent routing or conversational phrasing that would benefit from an LLM behavioral eval. LLM evaluation cannot approve either human gate.

## Known weaknesses and next adaptations

- Skill Studio currently reviews existing proposal packets; idea entry, human Markdown editing, and optional Mistral drafting/review remain a later bounded slice.
- Gate 1 authorizes implementation but does not invoke Codex. A working Beta must be produced through a separately reviewed implementation task.
- Existing legacy alpha generators still produce behavior scaffolds rather than working Betas; they are intentionally shown as non-runnable migration candidates.
- There is no production promotion implementation. Gate 2 records readiness for a future explicit promotion workflow only.
- Beta diagnostics intentionally store bounded skill-produced stdout and stderr locally because they are troubleshooting artifacts. The dashboard discloses this before execution.
- Visual density and interaction language require the owner's Opera GX review.

## Memory keys

No memory keys were added or used.

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled (contract preserved)
blocked_for_human_review
```

## Risk classification

```text
proposal listing/detail: Class 1 local read
proposal approval: Class 2 bounded local write
Beta listing/detail: Class 1 local read
Beta execution: risk inherited from Beta manifest plus mandatory human confirmation
Beta diagnostics: Class 2 bounded local append
Beta promotion approval: Class 2 bounded local write
production promotion: not implemented
```

## Human review checklist

- [ ] The three inventories communicate Production, Beta, and Proposal maturity clearly.
- [ ] Gate 1 language accurately limits approval to implementation work.
- [ ] Legacy alpha scaffolds are visibly non-runnable.
- [ ] A Beta cannot run without an exact human confirmation.
- [ ] Beta diagnostic disclosure is understandable.
- [ ] Test requirements, evidence, and weaknesses are reviewable.
- [ ] Gate 2 language does not imply that promotion has occurred.
- [ ] No automatic implementation, registration, promotion, or merge is present.
- [ ] Visual density, hierarchy, and responsive behavior are acceptable in Opera GX.
- [ ] Candidate is approved for merge only after review feedback is addressed.

## Human visual and product review outcome

```text
reviewed_at: 2026-07-15
reviewer: human owner
outcome: approved
```

The owner approved the Phase 12D Skill Studio visual and product slice after reviewing the live foreground dashboard in Opera GX. This approval satisfies the visual/product review gate. Repository merge remains a separate explicit gate.
