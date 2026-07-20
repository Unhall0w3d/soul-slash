# Conversational Music Revision Review

Status: Operator-approved

## Implemented

- Preserved a reviewed `revise` disposition as active per-conversation creative
  task state instead of terminating or silently generating another candidate.
- Added conservative continuation routing: revision discussion remains ordinary
  conversation; an explicit request is required to draft the revision.
- Reused `MusicRevisionDraftService` and the currently selected local provider
  to translate the stored review into a bounded revision candidate. Model output
  remains a visible draft and never becomes authorization.
- Displayed the complete revised Sound and Structure, BPM, key, time, preserved
  lyrics, rationale, and derived changes in Chat.
- Bound the action digest to the originating chat, flow, source candidate,
  complete revision draft, and current flow state.
- Reused Music Core validation plus the existing Music Studio revision preview
  and execution services.
- Returned the linked MP3/FLAC candidate to Chat and re-entered the existing
  human review loop.

## Files changed

- `lib/soul_core/conversation_creative_workflow_service.rb`
- `scripts/verify-conversational-creative-workflow.rb`
- `Soul/skills/registry.yaml`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`
- `docs/CURRENT_STATE.md`
- `docs/soul/CONVERSATIONAL_MUSIC_REVISION_BRIEF.md`
- `docs/assessments/CONVERSATIONAL_MUSIC_REVISION_REVIEW.md`

## Commands run and deterministic results

```text
ruby scripts/verify-conversational-creative-workflow.rb   PASS (31 checks)
ruby scripts/verify-chat-intent-and-interaction-boundary.rb PASS (35 checks)
ruby scripts/verify-music-revision-draft.rb               PASS
ruby scripts/verify-music-job-continuity.rb                PASS
ruby scripts/verify-core-orchestration.rb                  PASS
ruby scripts/verify-assistant-skill-catalog-phase43.rb     PASS
ruby -c changed Ruby files                                PASS
ruby bin/soul improve assistant-skill-catalog-refresh     PASS
node --check assets/dashboard/dashboard.js                PASS
git diff --check                                          PASS
```

## Local LLM evaluation

No local-model evaluation has been used as safety or approval evidence. The
candidate is designed for an Operator chat pass against the active local Core.
Any bounded live drafting probe will retain no transcript and will not execute
generation.

## Known weaknesses

- This slice covers music revision only. Visual guided revision, destructive
  rejection, keep/export, binding, final rendering, publication packaging, and
  upload remain separate exact Studio gates.
- The revision drafter receives recorded human review and candidate data. The
  existing Music Studio analysis integration remains the authoritative path for
  supplementing that review with machine-heard evidence.
- Revision quality still depends on the selected local model. Deterministic
  validation rejects malformed or overlong generation input but cannot promise
  musical improvement.
- A Core transition may be required again if the Operator changed Cores after
  the original candidate. The action reuses the existing active-work and lease
  checks.

## Memory and lifecycle

- Durable memory keys added: none.
- Skill-private memory stores added: none.
- Existing private task state used:
  `Soul/runtime/creative_flows/<chat_id>.json`.
- Lifecycle states touched: `awaiting_input`, `blocked_for_human_review`,
  `complete`, `failed`, and `canceled`.
- Persistent services, watchers, schedulers, and polling loops added: none.
- Risk classification: local revision drafting plus exact approval-gated bounded
  GPU generation.

## Human review checklist

- [ ] Record a music review with disposition `revise` from Chat.
- [ ] Confirm a casual revision mention remains ordinary conversation.
- [ ] Explicitly request the revision draft and inspect every visible field.
- [ ] Confirm intended lyrics and required project decisions remain unchanged.
- [ ] Click the exact revision action and confirm one linked candidate appears.
- [ ] Confirm the MP3 player and FLAC link open the revised candidate.
- [ ] Review the revised candidate again without leaving the originating chat.
- [ ] Confirm no rejection, export, binding, render, package, or publication was
  performed automatically.
- [x] Operator approved the candidate on 2026-07-19.
