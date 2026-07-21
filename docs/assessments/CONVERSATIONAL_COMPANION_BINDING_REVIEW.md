# Conversational Companion Binding Review

Status: Candidate-complete; awaiting Operator review

## Implemented

- Added explicit conversational binding for one exact kept Visual Studio
  candidate and one exact kept Music Studio candidate.
- Supported new/new, exact existing/existing, and mixed source flows. Newly
  generated sources require recorded `keep` reviews; existing sources retain
  the established exact-title kept-candidate lookup.
- Kept discussion inert and required a separate anchored binding request.
- Reused `VisualStudioService#promotion_preview` and `promotion_execute`,
  including their authoritative source hashes, candidate identities,
  downstream confirmation, and digest.
- Added an outer Chat digest over the conversation, flow, source identities,
  and exact downstream preview.
- Returned the music and image attachments with the bound companion record and
  stopped at `base_bound` for a later static-presentation review slice.
- Preserved a bound flow as active task context while allowing an explicit new
  creative request to supersede it safely.

## Files changed

- `lib/soul_core/conversation_creative_workflow_service.rb`
- `scripts/verify-conversational-creative-workflow.rb`
- `Soul/skills/registry.yaml`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`
- `docs/CURRENT_STATE.md`
- `docs/soul/CONVERSATIONAL_COMPANION_BINDING_BRIEF.md`
- `docs/assessments/CONVERSATIONAL_COMPANION_BINDING_REVIEW.md`

## Commands run and deterministic results

```text
ruby scripts/verify-conversational-creative-workflow.rb     PASS (55 checks)
ruby scripts/verify-conversation-visual-revision-planner.rb PASS (9 checks)
ruby scripts/verify-chat-intent-and-interaction-boundary.rb PASS (35 checks)
ruby scripts/verify-music-revision-draft.rb                 PASS
ruby scripts/verify-music-candidate-dispositions.rb         PASS
ruby scripts/verify-music-visual-companion.rb               PASS
ruby scripts/verify-music-job-continuity.rb                 PASS
ruby scripts/verify-core-orchestration.rb                   PASS
ruby scripts/verify-visual-studio-a2.rb                     PASS (17 checks)
ruby scripts/verify-assistant-skill-catalog-phase43.rb      PASS
ruby -c lib/soul_core/conversation_creative_workflow_service.rb PASS
node --check assets/dashboard/dashboard.js                  PASS
git diff --check                                            PASS
```

## Local LLM evaluation

No local-model evaluation is required for this deterministic identity and
approval slice. No model chooses candidates, previews the binding, or grants
authority.

## Known weaknesses

- The conversational continuation stops after binding. Static presentation,
  short review encoding, full-song rendering, package export, upload, and
  publication remain separate.
- Existing source selection remains exact-title based. Ambiguous or absent
  titles fail without mutation.
- Binding quality is a human creative judgment; deterministic validation proves
  identity, integrity, lineage, and authorization rather than aesthetic fit.
- A bound flow retains private task context until a future continuation,
  cancellation, or explicit new creative request supersedes it.

## Memory and lifecycle

- Durable memory keys added: none.
- Skill-private memory stores added: none.
- Existing private task state used:
  `Soul/runtime/creative_flows/<chat_id>.json`.
- Lifecycle states touched: `awaiting_input`, `blocked_for_human_review`,
  `complete`, `failed`, and `canceled`.
- Persistent services, watchers, schedulers, queues, and polling loops added:
  none.
- Risk classification: exact approval-gated local file copy into candidate
  lineage; no render or publication.

## Human review checklist

- [ ] Keep one generated song and one generated visual in the same Chat flow.
- [ ] Confirm binding discussion performs no preview or mutation.
- [ ] Explicitly request binding and inspect both source candidate identities.
- [ ] Confirm the preview says external publication is not included.
- [ ] Click the exact action and confirm one `base_bound` visual appears under
  the Music candidate.
- [ ] Confirm the source Music and Visual Studio candidates remain unchanged.
- [ ] Replay or refresh and confirm no duplicate binding appears.
- [ ] Confirm no presentation, video, package, upload, or publication was
  started.
