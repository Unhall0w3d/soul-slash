# Project Release Folders Review

Status: candidate-complete; human dashboard review pending

## What was implemented

- Reversible Active and Released classification for Music Studio and Visual
  Studio projects.
- Separate Active and Released list views with visible counts.
- One-click Move to Released and Restore to Active actions on selected projects.
- Release metadata stored inside the existing project directory without moving
  or renaming the project.
- Existing candidates, reviews, exports, generated artifacts, IDs, and
  cross-studio bindings remain untouched.

## Files changed

- `lib/soul_core/project_release_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-project-release-folders.rb`
- `docs/soul/PROJECT_RELEASE_FOLDERS_A0_BRIEF.md`
- `docs/assessments/PROJECT_RELEASE_FOLDERS_REVIEW.md`

## Commands and deterministic results

- `ruby -c lib/soul_core/project_release_service.rb` — PASS
- `ruby -c lib/soul_core/application_facade.rb` — PASS
- `node --check assets/dashboard/dashboard.js` — PASS
- `ruby scripts/verify-project-release-folders.rb` — PASS (8 checks)
- `ruby scripts/verify-music-studio-a3.rb` — PASS
- `ruby scripts/verify-visual-studio-a2.rb` — PASS (21 checks)
- `ruby scripts/verify-music-project-deletion.rb` — PASS
- `ruby scripts/verify-phase12b-in-process-application-api.rb` — PASS
- `git diff --check` — PASS

Legacy broad-dashboard verification was also attempted. Its feature-local checks
passed, but the aggregate remains blocked by pre-existing stale assertions:
Phase 12C expects exactly seven static routes while the current dashboard
allowlists twenty-one, and Phase 12C.1 still asserts that later-approved LAN and
service behavior is excluded. Neither condition was introduced or changed by
this slice.

Live authenticated dashboard verification:

- Music project moved from Active to Released, remained inspectable, and was
  restored to Active.
- Visual project moved from Active to Released, remained inspectable, and was
  restored to Active.
- Active and Released counts updated after each transition.
- Both test projects were restored to their original Active state.

## Local LLM eval results

None. Project classification and rendering are deterministic.

## Known weaknesses

- Released is one flat folder per studio; tags and nested collections are out of
  scope.
- A project must be selected before it can be released or restored.
- Legacy Phase 12C/12C.1 aggregate verifiers contain stale assumptions about the
  current dashboard and remain blocked independently of this feature.

## Memory keys added or used

None.

## Task lifecycle states touched

- `complete`
- `awaiting_input`
- `blocked_for_human_review`

## Risk classification

Low. Reversible local metadata only. No generation, deletion, publication,
privilege, persistence service, or network behavior is added.

## Human review checklist

- [x] Music Studio defaults to Active.
- [x] Visual Studio defaults to Active.
- [x] Releasing a project removes it from Active and shows it under Released.
- [x] Released projects remain fully inspectable.
- [x] Restoring returns the same project to Active.
- [x] Existing music/visual bindings still resolve.
- [ ] Mobile folder controls remain readable.
