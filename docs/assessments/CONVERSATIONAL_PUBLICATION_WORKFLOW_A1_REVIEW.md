# Conversational Publication Workflow A1 Review

Status: candidate complete; awaiting human review

## Implemented

- Extended the existing per-chat creative flow beyond exact companion binding.
- Reused the Music Studio static-presentation and full-duration rendering gates.
- Returned local review-loop and full-duration MP4 artifacts as authenticated
  Chat attachments.
- Preserved finished-song export as a separate exact action while keeping the
  publication workflow resumable.
- Reused the deterministic package-description, preview, digest, and local
  export gates.
- Added stale-action and idempotent-replay coverage.
- Added no upload, publication, watcher, queue, or unattended continuation.

## Files changed

- `lib/soul_core/conversation_creative_workflow_service.rb`
- `lib/soul_core/application_facade.rb`
- `Soul/skills/registry.yaml`
- `lib/soul_core/dashboard_capability_guide.rb`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`
- `docs/soul/CONVERSATIONAL_PUBLICATION_WORKFLOW_A1_BRIEF.md`
- `scripts/verify-conversational-publication-workflow-a1.rb`
- `docs/assessments/CONVERSATIONAL_PUBLICATION_WORKFLOW_A1_REVIEW.md`

## Commands and deterministic results

- `ruby scripts/verify-conversational-publication-workflow-a1.rb`
  - PASS: 12 checks.
- `ruby scripts/verify-conversational-creative-workflow.rb`
  - PASS: 60 checks.
- `ruby scripts/verify-dashboard-capability-guide-a1.rb`
  - PASS: 8 checks.
- `ruby scripts/verify-music-visual-companion.rb`
  - PASS: deterministic companion verification.
- `ruby scripts/verify-music-publication-package.rb`
  - PASS: deterministic publication-package verification.
- `ruby scripts/verify-visual-studio-native-video.rb`
  - PASS: deterministic native-video verification.
- `ruby bin/soul improve assistant-skill-catalog-refresh`
  - PASS: generated `docs/ASSISTANT_SKILL_CATALOG.md`.
- `ruby scripts/verify-assistant-skill-catalog-phase43.rb`
  - PASS: catalog, aliases, declared boundaries, and repo curation.
- `ruby scripts/verify-core-orchestration.rb`
  - PASS: Core orchestration candidate verification.
- `ruby scripts/verify-project-timeline-a1.rb`
  - PASS: Project Timeline deterministic verification.
- `git diff --check`
  - PASS.

## Local LLM evaluation

No local model is needed for the post-binding gates. Existing Studio records,
server-authored previews, exact digests, and human action clicks remain
authoritative.

## Known weaknesses

- Chat does not create or revise native motion candidates; it can continue only
  from an already reviewed/bound loop or a still requiring static presentation.
- Visual deletion and fine media trimming remain Studio-only.
- The upload package is local and upload-ready, but external account
  authentication, upload, scheduling, and publication are intentionally absent.

## Memory, lifecycle, and risk

- Durable memory keys added: none.
- Skill-private memory added: none.
- Private Project Timeline item `track_dashboard_skill_coverage` updated in
  place; private state remains ignored and was not staged.
- Persistent processes added: none.
- Risk: bounded local media encoding and local package export.
- External upload or publication: none.

## Human review checklist

- [ ] Static review loop appears in Chat with the expected source image.
- [ ] Full-duration companion appears in Chat and plays through the authenticated route.
- [ ] Finished-song export remains a separate action when the song is not already exported.
- [ ] Exact package description and destination are readable before export.
- [ ] Package completes locally without upload or publication.
- [ ] Replaying a completed action creates no duplicate artifacts.
