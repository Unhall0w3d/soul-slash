# Phase 12D.4 Proposal Lifecycle and Production Closeout Review

## What was implemented

- Added seven deterministic proposal stages derived from existing gates, Beta implementation/test evidence, and production registry state.
- Linked each canonical proposal to the exact `skill_id` in its Beta manifest and to production only when that ID has a non-empty production registry path.
- Added production-only closeout preview and execute operations with unchanged digest and literal confirmation.
- Added Skill Studio stage labels, linked production skill focus, deletion disclosure, and closeout controls.
- Cleared the three owner-identified old runtime proposals after confirming none contained a Beta; canonical proposal and Beta inventories are now empty.

## Files changed

- `lib/soul_core/skill_studio_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-phase12d4-proposal-closeout.rb`
- `docs/soul/PHASE12D_PROPOSAL_LIFECYCLE_CLOSEOUT_AMENDMENT.md`
- `docs/assessments/CONVERSATIONAL_SOUL_PHASE12D4_PROPOSAL_CLOSEOUT.md`
- supporting product, API, roadmap, current-state, milestone, and changelog documentation

## Commands run

```text
ruby -c lib/soul_core/skill_studio_service.rb
ruby -c lib/soul_core/application_contract.rb
ruby -c lib/soul_core/application_facade.rb
ruby -c scripts/verify-phase12d4-proposal-closeout.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-phase12d4-proposal-closeout.rb
git diff --check
```

The focused verifier, Phase 12D Skill Studio, Phase 12D.2 capability-gap intake, Phase 12D.3 Self Improvement, Phase 12E Review Center, Phase 12B/12C application and dashboard, authentication, protected deployment, runtime privacy, and repository-hygiene suites all passed.

## Deterministic test results

Focused verification passes all seven stages, exact skill linkage, Beta-only close refusal, production preview, wrong-confirmation refusal, stale-digest refusal, confirmed single-proposal deletion, production preservation, diagnostic preservation, contract allowlisting, safe UI rendering, and absence of polling.

All related aggregate regressions passed after the amendment was staged as intentional candidate work.

## Local LLM eval results

Not run. Stage, linkage, production identity, digest validation, and permanent deletion authorization are deterministic safety decisions and cannot be validated by an LLM.

## Known weaknesses

- Production linkage depends on the Beta manifest retaining the eventual production registry ID.
- Closeout is permanent and intentionally removes proposal-local gate evidence and the superseded Beta copy.
- There is no closed-proposal archive or restore operation.
- Legacy Alpha records remain outside this closeout workflow.
- A later formal promotion executor should register production and preserve release evidence before this closeout is used.

## Memory keys

None. The implementation uses canonical proposal, Beta, production registry, and shared diagnostic infrastructure; it creates no memory store.

## Task lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

Closeout is one bounded foreground operation and never waits after returning.

## Risk classification

```text
Class 4: permanent deletion of a validated production-linked proposal packet
```

## Human review checklist

- [ ] Seven stage names are understandable and ordered correctly.
- [ ] Linked skill identity is visible and unambiguous.
- [ ] Closeout appears only for an exact registered production skill.
- [ ] Preview clearly distinguishes deleted proposal/Beta data from preserved production/log data.
- [ ] Wrong confirmation and stale revision remain blocked.
- [ ] Post-close list and selection behavior are clear.
- [ ] Permanent deletion is acceptable without a closed-proposal archive.
- [ ] Visual/product approval is recorded before merge.

## Human review outcome

Approved by the human owner on 2026-07-15 with Phase 12E. Proposal stages, exact skill linkage, production-only closeout, and the disclosed deletion/preservation boundary are accepted for publication and merge. A separate Phase 12D.5 remains required for proposal-to-Beta implementation and Beta-to-production promotion.
