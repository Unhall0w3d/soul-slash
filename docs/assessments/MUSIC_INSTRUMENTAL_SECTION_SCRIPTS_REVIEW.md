# Music Instrumental Section Scripts Review

Status: candidate implementation verified; listening review pending

## Implemented

- Preserved bracket-only temporal scripts for instrumental projects.
- Rejected prose or lyric lines in instrumental mode.
- Passed the script through the exact generation input instead of silently replacing it with an empty string.
- Updated the dashboard guidance and submission behavior.

## Files changed

- `lib/soul_core/music_project_store.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/index.html`
- `scripts/verify-music-studio-a2.rb`
- `docs/soul/MUSIC_INSTRUMENTAL_SECTION_SCRIPTS_BRIEF.md`
- `docs/assessments/MUSIC_INSTRUMENTAL_SECTION_SCRIPTS_REVIEW.md`

## Commands and results

- `ruby -c lib/soul_core/music_project_store.rb` — PASS
- `node --check assets/dashboard/dashboard.js` — PASS
- `ruby scripts/verify-music-studio-a2.rb` — PASS (30 checks)
- `ruby scripts/verify-music-studio-a3.rb` — PASS (15 checks)
- `ruby scripts/verify-dashboard-click-approvals.rb` — PASS (6 checks)
- Isolated validation of Axiom Breaker, Chrome Tidal, and The Shape Between — PASS; all three generation-input scripts preserved
- `git diff --check` — PASS

## Live project reset

The Operator exact-confirmed deletion of five legacy-prompt projects. The bounded deletion service removed 40 project-owned files totaling 138,454,197 bytes and verified an empty Composition Archive. Finished external exports for Weather in the Wiring and Mercury Lattice were retained.

Three private 180-second project records were then created without starting generation:

- `music_a4557c610a5aa418` — Axiom Breaker; instrumental; D minor; dominant meter 7
- `music_b15dbfcd9cc3eaf5` — Chrome Tidal; instrumental; C# Phrygian; dominant meter 9
- `music_facc3537877e1728` — The Shape Between; vocal; G# minor; dominant meter 5

The final archive inventory contains exactly these three projects.

## Local LLM evaluation

None. This is a deterministic storage and generation-input boundary. Musical adherence requires human listening.

## Known weaknesses

- ACE-Step may not follow every requested meter transition.
- One dominant meter remains required in project metadata.
- Bracketed markers reduce vocalization risk but cannot guarantee an instrumental result.

## Memory and lifecycle

- Memory keys: none.
- Lifecycle states touched: `complete`, `awaiting_input`, and the unchanged downstream `blocked_for_human_review` generation gate.
- Persistent processes: none.

## Human review checklist

- [ ] Instrumental markers appear in the stored project and exact generation preview.
- [ ] Instrumental prose is rejected.
- [ ] Vocal project behavior is unchanged.
- [ ] Listening confirms markers improve section and meter behavior without introducing voice.
