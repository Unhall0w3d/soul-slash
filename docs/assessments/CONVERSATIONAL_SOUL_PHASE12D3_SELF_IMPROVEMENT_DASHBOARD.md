# Conversational Soul Phase 12D.3: Self Improvement Dashboard

> Current product label: **Self Assessment**. The historical phase and internal `self_improvement.*` application namespace retain their original names for compatibility and traceability.

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

## 2026-07-16 bounded-lifecycle repair

The owner reported that a manual Model Runtime assessment could remain visibly at `models · running` for more than an hour. Live inspection found no model assessment or inference job still executing; the model and dashboard services were healthy. The UI had entered its running state but did not replace that label when the request failed, and the service lacked one total assessment deadline around its individually bounded probes.

Candidate repair:

- all Self Improvement assessments have a 30-second backend foreground deadline;
- an overrun terminates as `failed` with no mutation;
- manual dashboard assessment requests have a 35-second browser deadline;
- every manual failure visibly changes the scope from `running` to `failed` and re-enables assessment controls;
- deterministic verification includes a deliberately slow model assessor.

No model, service, package, proposal, memory, or host state is changed by this repair.

## 2026-07-16 Self Assessment and signal-interface refresh

This candidate renames the user-facing surface to **Self Assessment** so evidence gathering is not confused with the future Self Augmentation concept. Historical phase names and the internal `self_improvement.*` operation namespace remain unchanged for compatibility.

Implemented:

- replaced the compact brand mark with a scalable Soul-specific signal-path SVG used by the banner, login gate, favicon, Chat empty state, and Skill Studio empty state;
- removed the two large arcane raster illustrations from active dashboard markup without deleting the historical source assets;
- shifted the interface toward near-black navy, teal operational emphasis, restrained violet, condensed headings, and scalable grid fields;
- calibrated interface copy against `docs/SOUL_PERSONALITY.md`, using Operator, signal, transmission, continuity, and capability only where each term describes a real product concept;
- preserved exact approval, lifecycle, authentication, mutation, and foreground-execution boundaries.

Files changed for this refresh include the dashboard HTML, CSS, JavaScript, SVG brand mark, application bootstrap label, current product documentation, and deterministic dashboard expectations.

Verification run:

```text
ruby scripts/verify-phase12d3-self-improvement-dashboard.rb  PASS
ruby scripts/verify-phase12c-foreground-dashboard.rb         PASS; visual review required
ruby scripts/verify-phase12d-skill-studio.rb                  PASS
ruby scripts/verify-phase12e-unified-review-center.rb         PASS
ruby scripts/verify-phase12b-in-process-application-api.rb    PASS
node --check assets/dashboard/dashboard.js                    PASS
git diff --check                                               PASS
git diff --cached --check                                      PASS
```

No local LLM eval was used for the visual change. No memory key, model, skill, service definition, host setting, or task lifecycle was added or changed. Risk remains bounded UI/documentation behavior with a required human visual review.

Refresh review checklist:

- [ ] The new mark remains recognizable in the banner and browser tab/bookmark.
- [ ] Chat and Skill Studio empty states scale cleanly at the owner's normal viewport.
- [ ] The palette and typography feel related to the owner's blog without copying its content.
- [ ] Soul's persona is present but does not obscure product meaning.
- [ ] Self Assessment is a clearer name than Self Improvement.
- [ ] Warnings, approval gates, and unavailable host changes remain visually distinct.
- [ ] Candidate is approved before commit or merge.

### Holistic readability and responsiveness revision

Following the first refresh review, the owner identified residual violet Self Assessment controls and unreadably small workflow, inventory, descriptive, and utility text. The candidate now:

- removes the legacy violet interaction RGB values across the stylesheet;
- assigns teal to active, available, selected, and verified interaction states;
- keeps amber for Operator attention and approval, and red for failed or destructive states;
- establishes an 11 px minimum utility scale, 12 px labels, 13–14 px supporting text, and 15 px conversational text through final cascade rules;
- enlarges the Skill Studio lifecycle steps, inventory headings, header description, card details, Review Center records, authentication copy, and dialog controls;
- revises Skill Studio and review language around capability development and explicit Operator authority;
- adds short, finite state- and interaction-driven transitions for panel arrival, focus, hover, and control engagement;
- respects `prefers-reduced-motion` and adds no JavaScript timer, polling, watcher, socket, or persistent process.

The Phase 12C assessor now deterministically verifies the readable type tokens, enlarged workflow/header rules, and absence of the legacy violet interaction value. The Phase 12C, Phase 12D, Phase 12D.3, and Phase 12E focused verifiers pass. Human review remains required because deterministic checks cannot establish comfort, hierarchy, or aesthetic quality at the owner's actual viewport.

### Gilded machine-soul redesign candidate

At the owner's direction, the signal-console visual candidate was superseded before approval by a researched, gilded magitech direction. The new candidate:

- uses `#060B11` as the low-luminance spatial canvas;
- uses metallic gold gradients for structural frames, hierarchy, nodes, and Operator gates;
- uses cerulean for Soul's active presence, available/verified state, and interaction paths;
- uses muted pale cyan-gray instead of white for long-form readability;
- reserves crimson for actual failure and destructive controls;
- replaces conventional card silhouettes with asymmetric curved frames and restrained corner structures;
- adds a new scalable gilded Soul core mark for banner, favicon, login, Chat, and Skill Studio;
- adds short `core-unseal`, `inscription-resolve`, and `core-awaken` CSS reactions with no infinite animation or fabricated throughput signal;
- retains the readable type-scale revision and every existing authentication, approval, lifecycle, and mutation boundary.

Research and deliberate adaptations are documented in `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`. This remains a visual-review candidate, not an approved merge.

### Square-one composition rebuild

The owner explicitly authorized redesigning the entire information architecture while retaining feature parity. The candidate therefore replaces the accumulated Phase 12 stylesheet plus visual overrides with one coherent stylesheet and recomposes the product surfaces around their purpose:

- Chat is the Soul Chamber: a suspended transmission archive, dominant conversation vessel, real lifecycle-driven Soul presence, and Operator-side system/model/workspace/inbox assembly.
- Skill Studio is the Capability Foundry: the five-stage mechanism is the primary hierarchy, with proposal, Beta, and production inventories feeding a single review vessel.
- Self Assessment is the Internal Observatory: assessment scopes surround a central core and project evidence into instrument-like environment, runtime, capability, model, recommendation, and proposal surfaces.
- Review Center is the shared Authority Chamber, retaining read-only approval and activity projections.
- Authentication and destructive dialogs use the same material, geometry, type, and state vocabulary.

The central Soul presence receives actual application lifecycle values (`pending`, `complete`, `failed`, and other declared states). Processing motion is finite—three iterations—and cannot continue as an unbounded ambient loop. Failed state uses the real failure lifecycle and crimson boundary. No operation, ID, confirmation phrase, API call, or stored data shape changed.

The clean rebuild retains an 11 px secondary-text floor, responsive folds at 1180/820/520 px, reduced-motion gating, focus visibility, semantic tabs and dialogs, and the existing no-polling/no-unsafe-DOM constraints.

### Square-one visual review outcome

```text
reviewed_at: 2026-07-16
reviewer: human owner
outcome: approved
approved_direction: gilded machine-soul composition
```

The owner reviewed the deployed square-one redesign and approved it as the dashboard visual and composition baseline. This approval covers the Soul Chamber, Capability Foundry, Internal Observatory, Authority Chamber, unified dialogs/authentication, scalable gilded core mark, readable type scale, and real-state finite reactions. It does not pre-approve future hierarchy changes or new product surfaces.
