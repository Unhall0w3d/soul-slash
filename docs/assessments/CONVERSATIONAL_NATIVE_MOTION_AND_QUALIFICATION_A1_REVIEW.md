# Conversational Native Motion and Qualification A1 Review

Status: candidate complete; awaiting human review

## Implemented

- Extended an active reviewed visual Chat flow into exact native
  text-to-video generation.
- Requires an explicit request, a 4-, 8-, or 12-second duration, and a
  chronological scene direction; only the optional seed is generated.
- Shows the exact FastWan profile, generation/delivery frame envelope,
  estimated runtime, publication boundary, and Core preflight before execution.
- Reuses Visual Studio's native preview, digest, execution, immutable archive,
  shared AMD lease, and timeout behavior.
- Returns the generated WebM as an authenticated Chat video attachment.
- Allows a stored Visual Studio `revise` motion review to unlock one exact
  linked native revision from Chat.
- Added a read-only Visual Studio qualification ledger over retained motion
  receipts and human reviews.
- Classified appropriate Chat coverage explicitly: structured motion review
  and binding, image-guided motion, destructive visual actions, Skill Studio
  promotion, Self Augmentation mutation, Review Center authority, and external
  publication retain their dedicated surfaces.

## Files changed

- `lib/soul_core/conversation_creative_workflow_service.rb`
- `lib/soul_core/visual_motion_qualification_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_capability_guide.rb`
- `lib/soul_core/phase12b_in_process_application_api_assessor.rb`
- `Soul/skills/registry.yaml`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-conversational-native-motion-a1.rb`
- `scripts/verify-dashboard-capability-guide-a1.rb`
- `docs/soul/CONVERSATIONAL_NATIVE_MOTION_AND_QUALIFICATION_A1_BRIEF.md`
- `docs/soul/CONVERSATIONAL_CREATIVE_STUDIO_BRIEF.md`
- `docs/guides/CONVERSATIONAL_CREATIVE_WORKFLOWS.md`
- `docs/guides/VISUAL_STUDIO.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/assessments/CONVERSATIONAL_NATIVE_MOTION_AND_QUALIFICATION_A1_REVIEW.md`

## Commands and deterministic results

- `ruby scripts/verify-conversational-native-motion-a1.rb`
  - PASS: 12 checks.
- `ruby scripts/verify-conversational-creative-workflow.rb`
  - PASS: 60 checks.
- `ruby scripts/verify-visual-studio-native-video.rb`
  - PASS.
- `ruby scripts/verify-visual-studio-generated-motion.rb`
  - PASS.
- `ruby scripts/verify-dashboard-capability-guide-a1.rb`
  - PASS: 8 checks.
- `ruby scripts/verify-core-orchestration.rb`
  - PASS.
- `ruby scripts/verify-conversational-publication-workflow-a1.rb`
  - PASS: 12 checks.
- `ruby scripts/verify-phase12b-in-process-application-api.rb`
  - PASS, including application allowlist, bounded bootstrap, lifecycle, and
    repo-curation regressions.
- `ruby scripts/verify-assistant-skill-catalog-phase43.rb`
  - PASS.
- `node --check assets/dashboard/dashboard.js`
  - PASS.
- `git diff --check` and `git diff --cached --check`
  - PASS.
- Live read-only qualification snapshot
  - PASS: 11 retained samples; 6 reviewed; human evidence at 4, 8, and
    12 seconds; 5 samples remain for Operator review.
- Local Dashboard browser verification
  - PASS: qualification ledger populated with no console errors.
  - PASS: no horizontal overflow at tested 1600×1000 or 1000×900 viewports.

## Local LLM evaluation

No local model is used to authorize native motion. This slice parses only an
explicit native-motion request, supported duration, and visible direction. The
existing structured creative planner remains responsible for the parent visual
brief. Human review in Visual Studio remains authoritative.

## Known weaknesses

- The first Chat-native motion request must continue an active reviewed visual
  flow; an arbitrary project title does not yet start this path in one turn.
- Motion review and motion-to-music binding remain in Visual Studio.
- Image-guided motion remains Visual Studio-only.
- Qualification evidence may have duration gaps until the Operator reviews
  representative retained candidates.
- Human ratings are intentionally not converted into an automatic production
  decision.

## Memory, lifecycle, and risk

- Durable memory keys added: none.
- Skill-private memory added: none.
- Private Project Timeline records are updated in place and remain ignored.
- Both previously `in_progress` items moved to `needs_review`; neither was
  silently marked validated or done.
- Persistent processes added: none.
- Lifecycle states: `awaiting_input`, `blocked_for_human_review`, `complete`,
  `failed`, and `canceled` through the existing creative flow.
- Risk: bounded local native-video generation with a disclosed Core transition.
- External upload or publication: none.

## Human review checklist

- [ ] Ask for native motion after keeping a Chat-created still.
- [ ] Confirm missing duration and missing direction each produce a focused question.
- [ ] Confirm the exact action discloses AMD-Free Core and the expected profile.
- [ ] Confirm the resulting WebM plays in Chat and appears in Visual Studio.
- [ ] Record `revise` in Visual Studio and request one linked revision in Chat.
- [ ] Review the qualification ledger on an ultrawide and narrow viewport.
- [ ] Confirm no motion review, binding, upload, or publication occurs implicitly.
