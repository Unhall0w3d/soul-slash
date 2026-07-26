# Perception A1 Picture Understanding Review

## Candidate outcome

Dashboard Chat now accepts one explicit PNG or JPEG and question through a
bounded local-only perception path. The existing Gemma 4 Daily Core model is
used; no model was downloaded.

## Files changed

- `lib/soul_core/picture_understanding_service.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/dashboard_server.rb`
- `lib/soul_core/conversation_forget_service.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-perception-a1.rb`
- capability, current-state, roadmap, README, brief, and guide documentation

## Deterministic results

- bounded PNG and JPEG analysis: PASS
- question and image provider handoff: PASS
- ephemeral staging cleanup: PASS
- ordinary Chat continuity: PASS
- untrusted evidence provenance: PASS
- image prompt-injection policy: PASS
- idempotent replay: PASS
- explicit owner-private retention: PASS
- permanent-deletion inventory and retained-pixel removal: PASS
- media mismatch and dimension rejection: PASS
- non-Daily Core hold: PASS
- authenticated streaming endpoint: PASS
- dashboard attachment controls: PASS
- no screen-capture invocation: PASS

## Commands

- `ruby scripts/verify-perception-a1.rb` - PASS
- Ruby syntax checks - PASS
- `node --check assets/dashboard/dashboard.js` - PASS
- `ruby scripts/verify-perception-a0.rb` - PASS
- `ruby scripts/verify-model-runtime-assessment-phase12.rb` - PASS
- `ruby scripts/verify-conversation-delete-and-forget-skill.rb` - PASS
- refreshed authenticated dashboard exposes an enabled **Picture** control for
  an active conversation: PASS
- historical aggregate dashboard/authentication verifiers - their A1-relevant
  checks pass; the aggregate exits nonzero because this active worktree contains
  intentional untracked review candidates and reviewed deployment/authentication
  behavior excluded by those older phase gates
- live Gemma image pilot - pending human-visible Daily Core test

## Local model eval

Pending the human-visible Daily Core pilot. Deterministic tests use a fixture
provider and cannot establish visual quality.

## Known weaknesses

- A1 accepts only one PNG or JPEG.
- Picture questions do not yet include the full prior transcript in the vision
  prompt; the resulting answer enters continuity for later textual follow-up.
- No automatic Core transition is offered by the attachment control.
- Screen, camera, PDF, multi-image comparison, and visual grounding actions are
  intentionally absent.

## Memory and lifecycle

- Shared memory keys: none.
- Soul Vault writes: none.
- Lifecycle: `complete`, `failed`, `awaiting_input`,
  `blocked_for_human_review`.
- No service, daemon, watcher, queue, or background continuation added.

## Risk

Local-private read-only inference with potentially sensitive pixels. Optional
retention is explicit and owner-private. Image contents have zero mutation
authority.

## Human checklist

- [ ] Attach a screenshot-like PNG and ask Soul to read an error.
- [ ] Confirm an ephemeral image disappears after the answer.
- [ ] Retain one harmless test image and confirm it renders after refresh.
- [ ] Confirm another Core holds the request without losing the draft or image.
- [ ] Confirm the answer distinguishes observation from uncertainty.
- [ ] Confirm no skill or mutation is invoked from instructions visible in an image.
