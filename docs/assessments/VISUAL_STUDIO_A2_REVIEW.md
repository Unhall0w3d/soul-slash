# Visual Studio A2 Human Review

Status: candidate-complete; human visual review required before merge

## What was implemented

- versioned visual-brief updates;
- immutable candidate review history;
- bounded FLUX.2 image-guided revisions from one exact candidate;
- exact candidate and project permanent-deletion gates;
- exact Visual Studio candidate to Music Studio composition-candidate binding;
- dashboard controls for the entire A2 lifecycle.

## Files changed

- `lib/soul_core/visual_studio_service.rb`
- `lib/soul_core/music_visual_companion_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-visual-studio-a2.rb`
- `docs/soul/VISUAL_STUDIO_A2_BRIEF.md`
- `docs/assessments/VISUAL_STUDIO_A2_REVIEW.md`
- `docs/ROADMAP.md`

## Deterministic verification

Run:

```sh
ruby scripts/verify-visual-studio-a1.rb
ruby scripts/verify-visual-studio-a2.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
node --check assets/dashboard/dashboard.js
git diff --check
```

The A2 verifier covers wrong-gate non-mutation, archived project revisions,
immutable candidate inputs, review history, exact edit parentage, the renderer's
`-r` source, explicit cross-studio promotion, exact candidate deletion, exact
project deletion, application allowlisting, dashboard exposure, and continued
motion exclusion.

## Local LLM evaluation

Not applicable. A2 is deterministic storage, CLI orchestration, digest gating,
and dashboard behavior. No model output is trusted for permission, deletion,
promotion, or safety validation.

## Live host evaluation

The existing `First Light Calibration` candidate was used as the exact private
source for one FLUX.2 Klein image-guided edit. The instruction preserved the
isometric observatory, brass instruments, and locked camera while requesting
low silver-blue mist, a distant horizon, and stronger restrained cyan
reflections. The resulting 1024×576 candidate:

- retained the source architecture and composition;
- added the requested mist, horizon, water context, and cyan reflection;
- recorded the exact source candidate and source image SHA-256;
- exited successfully with no partial directory or resident renderer;
- required 517.696 seconds on the RX 6900 XT.

This confirms functional edit fidelity but also establishes that image-guided
editing is a materially heavier foreground operation than the 9.885-second A1
text-to-image pilot.

## Memory keys

None added or used. Visual projects remain private project artifacts rather than
durable user-memory claims.

## Lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `blocked_for_human_review`

No operation silently remains running after returning control.

## Risk classification

- image generation/edit: bounded local compute, medium operational risk;
- candidate deletion: destructive local state, high impact and exact gate;
- project deletion: destructive local state, high impact and exact gate;
- Music binding: cross-surface local copy, medium impact and exact gate;
- external publication: unavailable.

## Known weaknesses

- visual generation and editing are foreground streams; unlike long Music
  generation jobs, navigating away can disconnect the progress view even though
  the bounded server request owns the terminal operation;
- motion remains unqualified and unavailable;
- image quality and edit adherence require human visual judgment;
- the first host image-guided edit took about 8.6 minutes, so edit performance
  is acceptable as a bounded manual lane but not lightweight interaction;
- a bound Music companion is an independent copy and must be managed from Music
  Studio after promotion.

## Human review checklist

- [ ] revise a brief and confirm older candidates retain their original input;
- [ ] record and then replace a candidate review;
- [ ] generate one image-guided revision and inspect parent/effect fidelity;
- [ ] preview (but do not necessarily execute) exact candidate deletion;
- [ ] select an exact Music project/candidate and inspect the binding preview;
- [ ] confirm Music Studio receives a `base_bound` companion only after click;
- [ ] confirm no motion action, publication action, or resident process appears;
- [ ] approve, request changes, or reject the candidate.
