# Music Vocal Feasibility and Failure Diagnostics A1 Review

## Candidate status

Candidate-complete for Operator review. This is not approval to merge or a claim that vocal adherence is solved.

## What was implemented

- A project-scoped, read-only vocal diagnostic service.
- Deterministic lyric-line syllable estimates and tag classification.
- Explicit detection of creative directions that compete with intelligibility.
- Structured candidate evidence covering reviewed, unreviewed, failed, partial, passed, and analyzed vocal attempts.
- Exclusion of historical instrumental candidates from vocal-outcome counts.
- A Music Studio evidence card that refreshes on project selection or on demand.
- Documentation and Timeline seed synchronization.

## Files changed

- `lib/soul_core/music_vocal_diagnostic_service.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-music-vocal-diagnostics-a1.rb`
- `Makefile`
- `docs/soul/MUSIC_VOCAL_FEASIBILITY_AND_FAILURE_DIAGNOSTICS_A1_BRIEF.md`
- `docs/guides/MUSIC_STUDIO.md`
- `config/project_tracker_seed.json`
- this review

## Deterministic evidence

- `ruby scripts/verify-music-vocal-diagnostics-a1.rb` — PASS, 10 checks.
- `ruby scripts/verify-music-studio-a2.rb` — PASS.
- `ruby scripts/verify-music-studio-a3.rb` — PASS.
- `ruby scripts/verify-music-studio-a3-vocal-analysis.rb` — PASS.
- `ruby scripts/verify-music-revision-draft.rb` — PASS.
- `ruby scripts/verify-music-qualification-a1.rb` — PASS, 10 checks.
- `node --check assets/dashboard/dashboard.js` — PASS.
- Ruby syntax checks for the new service, facade, and contract — PASS.

The retained evidence replay reported:

- the 57-second project as `repeated_adherence_failure`: three vocal candidates, two structured lyric failures, one unreviewed candidate, and four preflight risk classes;
- the 71-second project as `vocal_risk_detected`: two relevant vocal candidates, one excluded historical instrumental candidate, one structured lyric failure, and 20% retained machine sequence recall.

No model or audio generation was invoked.

## Local LLM eval

Not applicable. This slice is deterministic evidence projection; no LLM decides classification, authority, or recommendations.

## Known weaknesses

- Syllable counts are an English-oriented heuristic, not a phonetic model.
- ACE-Step may still omit or alter lyrics after a clear preflight.
- A risky brief may still produce excellent art; warnings describe tension with intelligibility, not musical quality.
- Only retained structured review fields and transcription evidence contribute to formal failure counts. Free-form notes remain visible elsewhere but are not converted into facts.
- This slice does not create an automatic repair or retry policy.

## Memory

No memory keys or private skill-local stores were added or used.

## Lifecycle states touched

- `complete`
- `awaiting_input` (delegated project validation)
- `blocked_for_human_review` (delegated retained-evidence integrity failure)

## Risk classification

Read-only local evidence. No privilege, persistence, network, destructive action, model invocation, project rewrite, generation, or approval mutation.

## Human review checklist

- [ ] Open the 57-second failed vocal project and confirm the card reports repeated structured failure without labeling the unreviewed candidate failed.
- [ ] Open the 71-second project and confirm the historical instrumental candidate is excluded from vocal counts.
- [ ] Confirm masking terms and unanchored performance tags match the actual brief.
- [ ] Confirm recommendations preserve the uncanny creative intent rather than prescribing generic pop structure.
- [ ] Confirm generation remains available and unchanged.
- [ ] Confirm an instrumental project reports `not applicable`.
