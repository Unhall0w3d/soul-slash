# Conversational Visual Revision Review

Status: Candidate-complete; awaiting Operator review

## Implemented

- Preserved a recorded visual `revise` disposition as active task context in
  its originating conversation.
- Added conservative continuation routing: casual revision discussion performs
  no drafting or visual operation, while an explicit visual revision request
  advances the flow.
- Added a bounded local-only planner that translates the stored human review
  and source-project metadata into one visible edit instruction, seed, and
  rationale. It is explicitly told that it has not seen the image pixels and
  receives no execution authority.
- Bound the chat action to the originating chat, flow, immutable source
  candidate, complete draft, and current flow digest.
- Reused AMD creative Core validation and Visual Studio's authoritative
  `edit_preview` and `edit_execute` gates.
- Returned the linked authenticated image to Chat and re-entered the normal
  human review loop.
- Made ambiguous combined music-and-visual revision requests require the
  Operator to name the intended medium instead of guessing.

## Files changed

- `lib/soul_core/conversation_visual_revision_planner.rb`
- `lib/soul_core/conversation_creative_workflow_service.rb`
- `scripts/verify-conversation-visual-revision-planner.rb`
- `scripts/verify-conversational-creative-workflow.rb`
- `Soul/skills/registry.yaml`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`
- `docs/CURRENT_STATE.md`
- `docs/soul/CONVERSATIONAL_VISUAL_REVISION_BRIEF.md`
- `docs/assessments/CONVERSATIONAL_VISUAL_REVISION_REVIEW.md`

## Commands run and deterministic results

```text
ruby scripts/verify-conversation-visual-revision-planner.rb PASS (9 checks)
ruby scripts/verify-conversational-creative-workflow.rb     PASS (48 checks)
ruby scripts/verify-chat-intent-and-interaction-boundary.rb PASS (35 checks)
ruby scripts/verify-music-revision-draft.rb                 PASS
ruby scripts/verify-music-candidate-dispositions.rb         PASS
ruby scripts/verify-music-job-continuity.rb                 PASS
ruby scripts/verify-core-orchestration.rb                   PASS
ruby scripts/verify-visual-studio-a2.rb                     PASS (17 checks)
ruby scripts/verify-assistant-skill-catalog-phase43.rb      PASS
ruby -c changed Ruby files                                  PASS
node --check assets/dashboard/dashboard.js                  PASS
git diff --check                                            PASS
```

## Local LLM evaluation

No local-model output is used as safety or approval evidence. The focused
planner verifier uses deterministic response fixtures. A live Operator chat
pass remains the appropriate quality evaluation for edit-instruction phrasing.

## Known weaknesses

- The planner works from project metadata and the Operator's review, not direct
  pixel inspection. The image is supplied only to the bounded guided-edit model
  after the exact action click.
- Edit quality depends on both the selected local chat model's translation and
  the local image model. Deterministic checks can reject malformed drafts but
  cannot promise visual improvement.
- Visual keep has no chat-native binding, render, package, deletion, or
  publication continuation in this slice; those remain separate Studio gates.
- A required Core transition can still block on active work or lease checks.

## Memory and lifecycle

- Durable memory keys added: none.
- Skill-private memory stores added: none.
- Existing private task state used:
  `Soul/runtime/creative_flows/<chat_id>.json`.
- Lifecycle states touched: `awaiting_input`, `blocked_for_human_review`,
  `complete`, `failed`, and `canceled`.
- Persistent services, watchers, schedulers, queues, and polling loops added:
  none.
- Risk classification: local draft plus exact approval-gated bounded GPU image
  edit.

## Human review checklist

- [ ] Record a visual review with disposition `revise` from Chat.
- [ ] Confirm a casual revision mention performs no draft or edit.
- [ ] Explicitly request a visual revision and inspect the full instruction,
  seed, source candidate, and rationale.
- [ ] Click the exact action and confirm one linked image appears in Chat.
- [ ] Confirm the source candidate remains unchanged in Visual Studio.
- [ ] Review the new candidate again from the originating conversation.
- [ ] Confirm no keep, deletion, binding, rendering, packaging, upload, or
  publication occurred automatically.
