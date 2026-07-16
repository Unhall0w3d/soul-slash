# Phase 12D.5 Gated Beta Build and Production Promotion Review

## What was implemented

- Added Gate-1-bound Beta workspace preview and preparation using an explicit canonical skill ID.
- Added an incomplete manifest, safe placeholder, implementation task pack, rollback notes, and required human review artifact without invoking Codex or another model.
- Added Gate-2-bound production promotion preview and execution for one self-contained reviewed Ruby entrypoint.
- Added exact byte hashes, fixed generated-skill paths, atomic new registry publication, production-local promotion receipts, and narrow failure cleanup.
- Added Skill Studio controls for both preview/confirmation workflows.

## Files changed

`CHANGELOG.md`, dashboard HTML/JavaScript, `docs/ARCHITECTURE.md`, roadmap/state/skills/API documentation, the Phase 12D.5 brief and this review artifact, `lib/soul_core/application_contract.rb`, `lib/soul_core/application_facade.rb`, `lib/soul_core/skill_studio_service.rb`, and `scripts/verify-phase12d5-gated-skill-promotion.rb`.

## Commands run

```text
node --check assets/dashboard/dashboard.js
ruby -c lib/soul_core/skill_studio_service.rb
ruby -c lib/soul_core/application_contract.rb
ruby -c lib/soul_core/application_facade.rb
ruby scripts/verify-phase12d5-gated-skill-promotion.rb
ruby scripts/verify-phase12d-skill-studio.rb
ruby scripts/verify-phase12d4-proposal-closeout.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
ruby scripts/verify-dashboard-authentication-phase12c1.rb
```

## Deterministic test results

Focused verification passes 16/16 checks covering Beta preparation boundaries, stale proposal rejection, no-replacement behavior, exact Gate 2 binding, disclosed promotion scope, wrong-confirmation and stale-registry rejection, exact-byte copy, atomic registry publication, receipt hashes, unrelated-state preservation, simulated registry-failure cleanup, application operations, dashboard preview ordering, safe DOM rendering, and absence of model/background primitives. Phase 12B, 12C, 12C.1, 12D, and 12D.4 regressions pass.

## Local LLM eval results

Not used for authorization or safety. No model invocation is part of either runtime operation.

## Known weaknesses

- Production promotion is intentionally limited to one self-contained Ruby entrypoint.
- Beta implementation still requires a human or separately invoked Codex development task.
- Automatic rollback is not implemented; the receipt provides exact manual rollback evidence.

## Memory keys

None. The workflow uses proposal, Beta, production registry, and review state rather than conversational memory.

## Task lifecycle states touched

`complete`, `failed`, `awaiting_input`, `canceled`, `blocked_for_human_review`.

## Risk classification

```text
Beta workspace preparation: Class 2 bounded local candidate write
Production promotion: Class 4 reviewed production code and registry mutation
```

## Safety and persistence check

No service, daemon, watcher, schedule, background loop, automatic model invocation, automatic approval, or unattended promotion is authorized.

## Human review checklist

- [ ] Gate 1 creates an honest incomplete Beta workspace.
- [ ] Codex/model invocation remains external and human-directed.
- [ ] Gate 2 preview identifies exact source, target, hashes, registry definition, and rollback.
- [ ] Promotion never replaces an existing skill.
- [ ] Production entrypoint bytes match the reviewed Beta.
- [ ] Failure rollback is narrow and predictable.
- [ ] Dashboard language clearly distinguishes preparation, implementation, approval, and promotion.
- [ ] Candidate is approved for merge.

## Human review outcome

Pending implementation and live review.
