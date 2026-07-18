# Music reference enrichment candidate review

## Candidate status

`candidate_complete` — the Operator approved and completed the pinned tooling
installation; a local end-to-end classifier smoke test passed.

## Implementation summary

- Unified new-reference analysis into one download and one bounded foreground
  pass: basic descriptors, rich semantic classifiers, and conditional transient
  CPU transcription.
- Added a separate pinned `essentia-tensorflow` environment and nine digest-bound
  official Essentia models so the existing basic analyzer remains isolated.
- Added exact-gated reanalysis for incomplete legacy profiles.
- Withheld source identity, raw extractor scalars, audio, and raw transcript from
  synthesis; synthesis now fails closed without versioned semantic evidence.
- Removed the redundant model-authored revision-summary array after live outputs
  showed both 20-item overflow and empty/malformed summaries. Soul now returns one
  cohesive generation-ready Sound and Structure block; code derives the review
  summary from exact changed fields. Truncated, embedded-list, and unchanged drafts
  fail before any generation starts.
- Conventional model meter notation is normalized only for recognized equivalents
  (`4/4` to Soul's compact `4`, `6/8` to `6`, and the other supported meters).
  Unsupported meters remain fail-closed.
- Revision packets bind the exact lyric-section sequence, including repeated
  markers. Model captions must time every occurrence in order, and the explicit
  section-duration total is deterministically rescaled when it exceeds the project
  target. The exact adjustment is shown for review; missing or reordered sections
  still fail closed and no generation starts automatically.

## Files changed

- `config/music_reference_enrichment_models.json`
- `scripts/soul-music-reference-enrich`
- `scripts/soul-music-reference-enrichment-tooling`
- `lib/soul_core/music_reference_analysis_service.rb`
- `lib/soul_core/music_reference_synthesis_service.rb`
- `lib/soul_core/music_reference_library_store.rb`
- `lib/soul_core/music_revision_draft_service.rb`
- `Makefile`
- application contract/facade, dashboard, deterministic verifiers, and design doc

## Commands and deterministic results

```text
ruby scripts/verify-music-reference-analysis-a5.rb     PASS
ruby scripts/verify-music-reference-synthesis-a5.rb    PASS
ruby scripts/verify-music-revision-draft.rb             PASS
python -m py_compile scripts/soul-music-reference-enrich PASS
ruby -c scripts/soul-music-reference-enrichment-tooling PASS
make music-reference-enrichment-check                 PASS
semantic analyzer on a generated 12-second WAV        PASS
node --check assets/dashboard/dashboard.js              PASS
git diff --check                                        PASS
```

No local LLM eval was run. The existing deterministic revision fixture reproduces
and accepts the 20-directive model output; semantic extraction needs the pinned
local tooling rather than an LLM safety judgment.

## Memory and lifecycle

- Shared memory keys read/written: none.
- Lifecycle states: `failed`, `awaiting_input`, `canceled`,
  `blocked_for_human_review`.
- Risk class: bounded network retrieval plus derived-evidence replacement.

## Known weaknesses

- Classifier labels and structural boundaries are fallible observations and are
  deliberately presented as evidence, not musical ground truth.
- A generated-audio smoke test validated all model APIs, but useful evidence
  quality still requires Operator review of a real reference reanalysis.
- The installer may consume an explicitly supplied local model cache, but only
  regular files matching every manifest byte count and SHA-256 digest are accepted.
- Reanalysis blocks approved or Fusion-dependent profiles rather than silently
  invalidating downstream approval.
- Raw audio/transcript are intentionally unavailable after terminal cleanup, so
  a later audit can inspect receipts and derived traits but cannot replay the source.

## Safety and human review checklist

```text
Persistent/background behavior added: no
Automatic install/download added: no
Confirmation gate weakened: no
Skill-private memory added: no
Source retention after return: no
[ ] Pinned packages/models and download size are acceptable
[ ] Derived evidence is useful without implying certainty
[ ] Reanalysis approval/fusion blockers are correct
[ ] Source identity withholding from synthesis is correct
[ ] Approve install plan for live validation
[ ] Approve candidate for commit/merge
```
