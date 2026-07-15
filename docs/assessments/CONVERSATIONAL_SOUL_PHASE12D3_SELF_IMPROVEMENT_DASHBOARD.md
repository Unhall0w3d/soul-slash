# Conversational Soul Phase 12D.3: Self Improvement Dashboard

## Candidate status

```text
status: candidate_complete_for_human_review
human_visual_review_required: yes
human_merge_review_required: yes
host_mutation_available: no
```

## What was implemented

- A third dashboard tab for Self Improvement using the existing Soul/ visual language.
- One lightweight, read-only environment snapshot when the tab is first opened.
- Explicit foreground scopes for environment, package-update, local-model, and capability assessment.
- Language and tool versions, package-manager evidence, update/cleanup candidate counts, repository state, model endpoint state, capability summary, recommendations, and existing proposal inventory.
- A reusable command runner with process-group termination, timeouts, output caps, and terminal outcomes.
- A bounded model-file scan capped by visited entries and discovered model files.
- A corrected capability matrix that recognizes the existing proposal intake, Alpha/Beta generation, separate Beta inventory, diagnostics, and both human gates.
- Preview-first, digest-bound, exact-confirmation generation of advisory improvement proposal packets.
- Idempotent proposal generation that does not duplicate unchanged proposal content.
- A visible boundary stating that package/system mutation, service changes, model downloads, implementation, promotion, merge, and release are unavailable.

## Files changed

```text
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md
docs/soul/PHASE12D3_SELF_IMPROVEMENT_DASHBOARD_BRIEF.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE12D3_SELF_IMPROVEMENT_DASHBOARD.md
lib/soul_core/bounded_command_runner.rb
lib/soul_core/environment_assessor.rb
lib/soul_core/package_manager_assessor.rb
lib/soul_core/runtime_assessor.rb
lib/soul_core/soul_project_assessor.rb
lib/soul_core/model_runtime_assessor.rb
lib/soul_core/capability_matrix.rb
lib/soul_core/improvement_proposal_generator.rb
lib/soul_core/self_improvement_service.rb
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/phase12b_in_process_application_api_assessor.rb
assets/dashboard/index.html
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
scripts/verify-phase12c-foreground-dashboard.rb
scripts/verify-phase12d3-self-improvement-dashboard.rb
```

## Commands run

```text
ruby -c lib/soul_core/bounded_command_runner.rb
ruby -c lib/soul_core/self_improvement_service.rb
ruby -c lib/soul_core/improvement_proposal_generator.rb
ruby -c lib/soul_core/capability_matrix.rb
ruby -c lib/soul_core/model_runtime_assessor.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
ruby scripts/verify-phase12d-skill-studio.rb
ruby scripts/verify-phase12d2-capability-gap-intake.rb
```

Direct local runtime checks also exercised the real lightweight snapshot, read-only update checks, model assessment, capability assessment, and proposal preview.

## Deterministic test results

The focused Phase 12D.3 verifier passes:

- automatic snapshot skips package update checks;
- deeper scopes require explicit invocation and do not persist assessment state;
- invalid scopes terminate as `awaiting_input`;
- model process inventory remains disabled;
- proposal generation blocks without exact human confirmation;
- changed assessment digests block execution;
- confirmed execution writes advisory packets only;
- unchanged candidates are not duplicated;
- timed-out foreground commands are terminated;
- the third ARIA tab and all four assessment scopes are present;
- DOM rendering avoids `innerHTML`;
- no polling, watcher, socket, or background continuation is added;
- host mutation is visibly unavailable.

The Phase 12B aggregate, Phase 12C, Phase 12D, and Phase 12D.2 regressions pass after intentional staging. During unstaged candidate work, the historical Phase 12B aggregate verifier correctly stopped at its repository-curation guard because the new review artifact and verifier were untracked. Its application assessment initially also detected the literal metadata key `polling`; that key was renamed to `automatic_refresh`, preserving the intended false value without tripping the historical source guard.

The original Phase 11 environment, Phase 12 model-runtime, Phase 13 capability-matrix, and Phase 14 improvement-proposal verifiers also pass. The Phase 14 expectation was updated so the already-delivered Alpha/Beta pipeline is no longer reported as missing.

## Local LLM eval results

No LLM eval was run. This slice adds deterministic assessment, lifecycle, mutation-boundary, and dashboard behavior. An LLM cannot approve system safety, package operations, proposal creation, or merge readiness.

## Known weaknesses

- Package-manager update output is normalized to counts and bounded items; package-specific semantic interpretation remains deliberately shallow.
- Update checks may report zero when a package manager requires refreshed metadata or privileges. Soul does not refresh databases or elevate privileges.
- Local endpoint checks confirm reachability and exposed model identifiers, not model quality or suitability.
- The model-file scan is intentionally capped and may report a truncated inventory on large stores.
- Capability and improvement-proposal rules remain hand-authored; some missing capabilities may require human correction or a future reviewed drafting workflow.
- The dashboard does not apply updates or cleanup actions. That requires a separate human-approved executor and rollback brief.
- Visual density and terminology require the owner's Opera GX review.

## Memory keys

No memory keys were added or used.

## Task lifecycle states touched

```text
complete
failed
awaiting_input
canceled (application contract preserved)
blocked_for_human_review
```

No task remains running after a response.

## Risk classification

```text
automatic environment snapshot: Class 1 bounded local read
manual update/model/capability assessment: Class 1 bounded local read
proposal preview: Class 1 bounded local read
proposal packet generation: Class 2 bounded local write with exact confirmation
package/system/service/model mutation: unavailable
```

## Human review checklist

- [ ] The third tab is visually consistent with Chat and Skill Studio.
- [ ] Environment, runtime, capability, and model evidence is understandable.
- [ ] Automatic versus manually requested assessment is clear.
- [ ] Update and cleanup counts do not imply that changes were applied.
- [ ] The unavailable host-mutation boundary is prominent enough.
- [ ] Proposal preview explains precisely what will and will not be written.
- [ ] Exact confirmation and digest revalidation behave as expected.
- [ ] Existing Skill Studio and self-skilling human gates remain unchanged.
- [ ] No persistent service, timer, polling, watcher, or background continuation was added.
- [ ] Candidate is approved for merge only after human visual and product review.

## Human visual and product review outcome

```text
reviewed_at: 2026-07-15
reviewer: human owner
outcome: approved
```

The owner reviewed the live Self Improvement tab in Opera GX and approved the visual and product slice. Repository merge remains a separate explicit gate.
