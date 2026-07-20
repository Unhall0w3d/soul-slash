# Chat Intent and Interaction Hardening Review

Status: accepted for merge; Qwen reserve live evidence remains deferred

## Implemented

- Added `ConversationRequestShape`, a deterministic prerequisite that separates
  action requests, informational questions, terse requests, and conversational
  context before domain routing.
- Applied that prerequisite to legacy intent routing, deterministic tool
  matching, declared capability resolution, research, artifact creation, and
  initial creative-workflow detection.
- Preserved natural lead-ins such as `Well, take a look...` while preventing
  statements about status, skills, research, artifacts, and creative work from
  silently invoking them.
- Changed unavailable-capability support questions to information-only. An
  explicit task remains eligible for the existing review-gated proposal intake.
- Added one foreground retry when a successful local provider response contains
  no text. The retry limit is exactly one and is reported in response metadata.
- Expanded the response guard for live-observed invented scene-setting,
  background activity, costume narration, unprompted time greetings, and
  parenthetical machine stage directions. Avatar description remains available
  when the Operator is actually discussing the avatar.

## Files changed

Runtime:

- `lib/soul_core/conversation_request_shape.rb`
- `lib/soul_core/intent_router.rb`
- `lib/soul_core/conversation_tool_catalog.rb`
- `lib/soul_core/conversation_capability_registry.rb`
- `lib/soul_core/conversation_artifact_decision_policy.rb`
- `lib/soul_core/conversation_creative_planner.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `lib/soul_core/conversation_response_truth_guard.rb`
- `lib/soul_core/conversation_runtime.rb`

Verification and documentation:

- `scripts/verify-chat-intent-and-interaction-boundary.rb`
- `scripts/run-live-chat-intent-evaluation.rb`
- `docs/CONVERSATIONAL_ORCHESTRATOR.md`
- `docs/soul/CHAT_INTENT_AND_INTERACTION_HARDENING_BRIEF.md`
- `docs/assessments/CHAT_INTENT_AND_INTERACTION_HARDENING_REVIEW.md`

## Commands run and deterministic results

```text
ruby scripts/verify-chat-intent-and-interaction-boundary.rb       PASS (35 checks)
ruby scripts/verify-conversational-creative-workflow.rb           PASS (25 checks)
ruby scripts/verify-live-persona-contract.rb                      PASS
ruby scripts/verify-phase12d2-capability-gap-intake.rb            PASS
ruby scripts/verify-phase11-artifact-metadata-attachment.rb       PASS
ruby scripts/verify-phase11c-bounded-artifact-creation.rb         PASS
ruby scripts/verify-responsive-chat-and-web-research.rb           functional checks PASS; exits on the pre-existing ClientDisconnected fixture mismatch
ruby scripts/verify-conversational-orchestrator-phase4.rb         functional checks PASS; curation gate stops on this candidate's intentionally untracked verifier
ruby -c changed Ruby files                                       PASS
git diff --check                                                  PASS
```

## Local LLM evaluation

The ephemeral local-only evaluation completed three ordinary conversation
prompts through `soul-local-chat`. Every prompt routed to `direct_model`; no
deterministic tool, skill catalog, host evidence, or cloud fallback ran.

The run also exposed useful model behavior rather than hiding it:

- several early samples generated environmental or costume scene-setting
  despite the prompt contract; those concrete forms became deterministic guard
  fixtures;
- three fresh runs returned an empty first greeting while later turns worked;
  this produced the one-retry foreground repair;
- after the retry repair, all three turns completed as model responses;
- the final live sample exposed one additional `quiet hum of processing` phrase,
  which is now covered by the same scene-narration guard and focused test.

No evaluation transcript or private model context was retained. Local model
output did not decide routing, safety, approval, or merge readiness.

## Known weaknesses

- Natural language remains open-ended. The shared classifier is intentionally
  conservative and domain routing still validates the requested operation.
- Qwen reserve persona and routing behavior still requires a live human pass
  when that Core is active.
- Gemma continues to search for machine-fantasy metaphors even when instructed
  not to. Deterministic guards can remove known classes, but human conversation
  review remains more meaningful than claiming perfect stylistic compliance.
- The one empty-response retry improves first-turn resilience but does not hide
  a second empty response; the runtime returns its existing explicit fallback.
- The historical responsive-chat verifier still expects a swallowed broken pipe
  while the current server deliberately raises `ClientDisconnected`. That
  unrelated fixture mismatch predates this slice.

## Memory and lifecycle

- Durable memory keys added: none.
- Skill-private memory stores added: none.
- Persistent processes added: none.
- Lifecycle states changed: none; this slice selects existing bounded paths.
- Risk classification: conversational routing repair; existing downstream risk
  and approval gates remain authoritative.

## Human review checklist

- [ ] Ordinary status and skill mentions remain conversational.
- [ ] Explicit status and catalog requests still work.
- [ ] Support questions do not create capability-gap proposals.
- [ ] Explicit unsupported tasks retain the reviewed proposal intake path.
- [ ] Core discussion does not switch a Core; the exact command creates only a
  preview action.
- [ ] Creative discussion does not start a project; an explicit request does.
- [ ] Research and artifact history statements remain conversation.
- [ ] Gemma responses remain natural and do not dump unrelated capabilities.
- [ ] Qwen reserve receives the same live conversational review when activated.
- [x] Operator approved continuation to the next slice on 2026-07-19.
