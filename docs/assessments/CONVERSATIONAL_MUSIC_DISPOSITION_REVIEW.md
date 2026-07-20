# Conversational Music Disposition Review

Status: Operator-approved

## Implemented

- Kept recorded music `keep` and `reject` dispositions available as bounded
  originating-chat task state.
- Required a separate explicit export or deletion request; casual discussion
  does not prepare or execute an operation.
- Reused `MusicCandidateDispositionService` for authoritative previews and
  execution rather than duplicating file, digest, receipt, or path behavior.
- Displayed the exact finished-song destination/files/non-overwrite boundary or
  rejected-candidate deletes/retains/descendant scope before the action.
- Bound each Chat action to the current flow plus the downstream disposition
  preview and revalidated downstream state at execution.
- Returned a local export destination without uploading or publishing.
- Removed a rejected candidate from the active flow only after the existing
  tombstoned deletion completed.
- Allowed a new explicit creative request to close an unconsumed disposition
  flow and begin a new brief.

## Files changed

- `lib/soul_core/conversation_creative_workflow_service.rb`
- `lib/soul_core/application_facade.rb`
- `scripts/verify-conversational-creative-workflow.rb`
- `Soul/skills/registry.yaml`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`
- `docs/CURRENT_STATE.md`
- `docs/soul/CONVERSATIONAL_MUSIC_DISPOSITION_BRIEF.md`
- `docs/assessments/CONVERSATIONAL_MUSIC_DISPOSITION_REVIEW.md`

## Commands run and deterministic results

```text
ruby scripts/verify-conversational-creative-workflow.rb   PASS (41 checks)
ruby scripts/verify-chat-intent-and-interaction-boundary.rb PASS (35 checks)
ruby scripts/verify-music-candidate-dispositions.rb       PASS
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

None required for the deterministic disposition boundary. Model output neither
previews nor authorizes export or deletion. Operator language still receives a
human live pass through Chat.

## Known weaknesses

- Visual review currently supports `keep` and `revise`, not `reject`; visual
  guided revision and deletion remain dedicated Visual Studio gates.
- Music/visual binding, final rendering, publication packaging, upload, and
  publication remain outside this slice.
- A kept vocal song still requires completed transcription before the existing
  export service will produce the finished folder.
- An existing finished export intentionally blocks later candidate rejection
  until a separate reviewed export-removal design exists.

## Memory and lifecycle

- Durable memory keys added: none.
- Skill-private memory stores added: none.
- Existing private task state used:
  `Soul/runtime/creative_flows/<chat_id>.json`.
- Lifecycle states touched: `awaiting_input`, `blocked_for_human_review`,
  `complete`, `failed`, and `canceled`.
- Persistent processes added: none.
- Risk classification: local finished-song export or permanent candidate-owned
  deletion behind existing exact previews and a separate click.

## Human review checklist

- [ ] Record `keep`, then confirm ordinary export discussion does nothing.
- [ ] Explicitly request export and inspect destination, files, overwrite, and
  publication boundaries.
- [ ] Click export and confirm the exact finished folder is reported.
- [ ] Record `reject`, then confirm ordinary deletion discussion does nothing.
- [ ] Explicitly request deletion and inspect deletes, retains, and descendants.
- [ ] Click deletion and confirm the candidate player disappears while the
  rejection receipt remains in Music Studio lineage.
- [ ] Confirm a kept candidate cannot prepare rejection and a rejected candidate
  cannot prepare export.
- [ ] Confirm a new song request can supersede an unconsumed disposition choice.
- [x] Operator approved the candidate on 2026-07-19.
