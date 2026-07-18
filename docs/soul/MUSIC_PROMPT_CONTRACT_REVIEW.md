# Music Prompt Contract Review

Status: candidate-complete for human review

## What was implemented

- Aligned the Music composition form with the pinned ACE-Step input contract:
  Sound and Structure is the overall sonic portrait, Lyrics and section markers
  is the temporal script, and BPM/key/time remain dedicated metadata.
- Added short, visible examples to the new-composition form and equivalent
  guidance to revision inputs.
- Let the desktop Composition Archive consume its available column height while
  preserving a bounded scroll area on narrow screens.
- Updated reference-profile and fusion synthesis prompts to produce the same
  field separation without artist or song names.
- Updated Soul revision drafts to return a clean generation caption. Human
  change summaries remain separate review evidence and are no longer appended
  to the caption sent to ACE-Step.
- Rejected new projects, revisions, and profile synthesis candidates that embed
  BPM, key, meter, exact section seconds, or revision directives in Sound and
  Structure. Existing immutable projects remain readable for compatibility.
- Created four private, original composition projects for the Operator's
  progressive complexity trial. No audio generation was started.

## Files changed

- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `lib/soul_core/music_project_store.rb`
- `lib/soul_core/music_reference_synthesis_service.rb`
- `lib/soul_core/music_revision_draft_service.rb`
- `scripts/verify-music-studio-a2.rb`
- `scripts/verify-music-reference-synthesis-a5.rb`
- `scripts/verify-music-revision-draft.rb`
- `docs/soul/MUSIC_PROMPT_CONTRACT_REVIEW.md`

Private local project artifacts were created under ignored
`Soul/music/projects/` storage for Static Geometry, Mercury Lattice, Weather in
the Wiring, and Teeth of the Signal.

## Commands run and deterministic results

- `ruby scripts/verify-music-studio-a2.rb` — pass
- `ruby scripts/verify-music-studio-a3.rb` — pass
- `ruby scripts/verify-music-reference-synthesis-a5.rb` — pass
- `ruby scripts/verify-music-revision-draft.rb` — pass
- `ruby scripts/verify-dashboard-click-approvals.rb` — pass
- `node --check assets/dashboard/dashboard.js` — pass
- `ruby -c lib/soul_core/music_project_store.rb` — pass
- `ruby -c lib/soul_core/music_reference_synthesis_service.rb` — pass
- `ruby -c lib/soul_core/music_revision_draft_service.rb` — pass
- `git diff --check` — pass

## Local LLM eval results

None. This pass changes deterministic prompt boundaries and prepares human
listening candidates; it does not use model output as approval.

## Known weaknesses

- ACE-Step text conditioning remains probabilistic. Correct field structure
  cannot guarantee genre, vocal technique, lyric, or section adherence.
- Existing immutable projects with legacy overloaded captions remain readable
  and visible. They are not silently rewritten.
- The artist-profile bridge supplies reviewed derived traits as text. It does
  not yet use source audio or semantic audio codes as generation conditioning.
- Controlled vocal-fry and dual-vocal behavior are an explicit experiment in
  the fourth project, not a claimed checkpoint capability.

## Memory keys added or used

None. Projects remain private Music domain artifacts rather than shared
personality memory.

## Task lifecycle states touched

- `complete` for project creation and deterministic inspection.
- `awaiting_input` for malformed or overloaded new captions.
- `blocked_for_human_review` at every generation preview and listening gate.
- `failed` remains the terminal state for quarantined generation failures.

## Risk classification

Low-to-medium. The implementation narrows accepted generation inputs and adds
private project records. It starts no model, service, queue, retry, or
background process.

## Human review checklist

- [ ] The composition form clearly explains the sonic-caption/temporal-script
      split without making the interface noisy.
- [ ] Artist-profile synthesis produces a clean caption and concise section
      tags on its next human-reviewed draft.
- [ ] Static Geometry establishes the intended instrumental genre baseline.
- [ ] Mercury Lattice adds technical and saxophone complexity without losing
      that baseline.
- [ ] Weather in the Wiring attempts all 12 supplied lyric lines.
- [ ] Teeth of the Signal distinguishes clean tenor and controlled unclean
      passages across all 25 supplied lyric lines.
- [ ] No project generation begins before the Operator clicks its exact gate.
