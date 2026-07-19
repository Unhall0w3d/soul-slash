# Conversational Creative Studio and Persona Candidate Review

Status: candidate-complete; awaiting Operator chat review

## Implemented

- Added strict conversational creative routing. A topical mention is not an invocation; an explicit action or answer inside an active flow is required.
- Added private per-conversation creative task state with bounded size, atomic owner-only writes, cancellation, explicit terminal states, and no watcher, service, resident model, or polling loop.
- Added structured local-model planning for Music, Visual, and combined candidate briefs. Music preserves the four user-required decisions: intent, supported duration, vocal/instrumental mode, and rights status. Optional fields remain visible before execution.
- Added exact click-authored generation actions bound to the flow digest and action identity. Music/combined work selects Music Core; visual-only work selects AMD-Free Core. Runtime state is revalidated before mutation.
- Added authenticated audio and image attachments to Chat.
- Added structured review translation and a second exact action that records Music and Visual Studio reviews without silently revising, rejecting, binding, exporting, or publishing.
- Added strict standalone Core requests such as `Switch to Music Core`, using the existing Core preview/digest/execute service. Discussion about a Core is not an invocation.
- Registered and regenerated assistant-facing entries for music production, visual production, companion production, and Core activation.
- Recalibrated Soul from the softer apprentice/familiar framing to an awakened-artificer persona derived from the approved avatar's composure, precision, restrained warmth, aesthetic judgment, and lucid curiosity.
- Added explicit anti-patterns for sleepy freshness, fantasy-narrator scene setting, ceremonial deference, aloofness, and skill-catalog over-triggering.
- Added a compact projection of the same version 8 identity for the Qwen NVIDIA reserve; it preserves essential voice and truth boundaries without creating a second persona.

## Files changed

Core implementation:

- `lib/soul_core/conversation_creative_flow_store.rb`
- `lib/soul_core/conversation_creative_planner.rb`
- `lib/soul_core/conversation_creative_review_planner.rb`
- `lib/soul_core/conversation_creative_workflow_service.rb`
- `lib/soul_core/conversation_core_workflow_service.rb`
- `lib/soul_core/conversation_runtime.rb`
- `lib/soul_core/conversation_orchestration_contract.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_music_job_manager.rb`
- `lib/soul_core/intent_router.rb`
- `lib/soul_core/conversation_context_builder.rb`
- `lib/soul_core/conversation_identity_profile.rb`
- `lib/soul_core/phase10_identity_style_foundation_assessor.rb`
- `Soul/skills/registry.yaml`
- `lib/soul_core/assistant_skill_catalog.rb`

Interface and documentation:

- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`
- `docs/soul/CONVERSATIONAL_CREATIVE_STUDIO_BRIEF.md`
- `docs/assessments/SOUL_PERSONA_AND_AVATAR_ALIGNMENT_RESEARCH.md`
- `docs/SOUL_PERSONALITY.md`
- `docs/soul/IDENTITY_AND_STYLE_POLICY.md`
- `docs/BRANDING.md`
- `docs/soul/DASHBOARD_PRODUCT_AND_VISUAL_DIRECTION.md`
- `README.md`
- `docs/CURRENT_STATE.md`
- `docs/ARCHITECTURE.md`
- `docs/soul/MULTI_MODEL_AND_MUSIC_STUDIO_ARCHITECTURE.md`
- `docs/ASSISTANT_SKILL_CATALOG.md`

Verification:

- `scripts/verify-conversational-creative-workflow.rb`
- `scripts/verify-soul-personality-foundation-phase40.rb`
- `scripts/verify-live-persona-contract.rb`
- `scripts/verify-phase10-inspectable-interests-closeout.rb`
- `scripts/verify-conversational-architecture-phase1.rb`

## Commands and deterministic results

```text
ruby scripts/verify-conversational-creative-workflow.rb       PASS (21 checks)
ruby scripts/verify-soul-personality-foundation-phase40.rb    PASS
ruby scripts/verify-live-persona-contract.rb                  PASS
ruby scripts/verify-core-orchestration.rb                     PASS
ruby scripts/verify-music-job-continuity.rb                   PASS
ruby scripts/verify-music-studio-a2.rb                        PASS
ruby scripts/verify-music-studio-a3.rb                        PASS
ruby scripts/verify-visual-studio-a1.rb                       PASS (12 checks)
ruby scripts/verify-visual-studio-a2.rb                       PASS (17 checks)
node --check assets/dashboard/dashboard.js                    PASS
ruby -c changed Ruby runtime files                            PASS
git diff --check                                              PASS
```

The older phase-wide verifiers that require a completely clean curation state were initially blocked only by this slice's new untracked verifier and passed after candidate files were intentionally staged. Phase 10, Phase 11A, and Phase 12B compatibility regressions also pass after updating their stale identity/brand assertions to the current canonical direction. The responsive-chat verifier contains a pre-existing disconnect expectation that conflicts with the current explicit `ClientDisconnected` server behavior; that unrelated assertion is not treated as validation for this slice.

## Local LLM evaluation

No synthetic local-model persona score is being substituted for the Operator's real conversation review. The structured planner and review parser are deterministically tested with fixed provider outputs. One bounded read-only live planner probe against the configured Daily provider correctly classified an original 90-second instrumental request, preserved all four supplied requirements, returned no missing fields, and produced a valid 107-character Sound and Structure block. Its first response omitted the optional title; that evidence caused the deterministic optional-field completion repair. The repeated probe returned a nonempty title, 80 BPM, 4/4 meter, and no missing requirements. No project, candidate, flow, Core mutation, or live chat was created by either probe.

The morning test conversations remain the intended persona and multi-turn behavioral evaluation against live Gemma and Qwen Cores; their responses should be preserved for review before merge.

## Known weaknesses and deliberate boundaries

- Candidate creation and review are chat-native. Revision generation, destructive rejection, visual binding, static companion rendering, final export, upload-package export, and external publication retain their existing dedicated Studio gates. `creative.companion_production` is therefore registered as `partial` rather than overstated as complete.
- Required-field extraction still uses the configured local structured-output model to interpret free-form language. Deterministic code validates enums, limits, exact source titles, and user-supplied provenance, but real conversational ambiguity still needs Operator evaluation.
- A standalone Core action updates the action status and global Core panels; it does not append a synthetic second assistant message claiming success.
- The Qwen reserve keeps the same stable identity through a smaller runtime prompt path; persona fidelity during Music/AMD-Free Core remains a human test item.

## Memory and lifecycle

- Durable memory keys added: none.
- Skill-private memory stores added: none.
- Private task state: `Soul/runtime/creative_flows/<chat_id>.json`, ignored and bounded to 256 KiB.
- Lifecycle states touched: `awaiting_input`, `blocked_for_human_review`, `complete`, `failed`, `canceled`.
- Risk classification: local state write, bounded GPU generation, runtime mutation, and human-reviewed candidate state.

## Human review checklist

- [ ] Saying `I am working on your skills` remains ordinary conversation.
- [ ] Asking `What skills do you have?` still produces the catalog.
- [ ] An explicit song request asks only for omitted required choices.
- [ ] Optional music fields are coherent, visible, editable in conversation, and the Sound and Structure block stays within 512 characters.
- [ ] An explicit image request uses AMD-Free Core; music and combined requests use Music Core.
- [ ] Clicking the exact action persists across navigation and returns a playable/viewable candidate.
- [ ] Candidate feedback becomes a faithful visible review rather than an automatic keep or revision.
- [ ] Repeated action clicks do not duplicate generation or reviews.
- [ ] Direct Core requests are strict and discussion does not switch anything.
- [ ] Soul feels poised, attentive, curious, aesthetically aware, and slightly strange without sleepy scene-setting, Dungeon-Master narration, flattery, or sterile aloofness.
- [ ] Revision, rejection, binding, export, and publication boundaries are stated honestly.
- [ ] Operator explicitly approves or requests corrections before commit/merge.
