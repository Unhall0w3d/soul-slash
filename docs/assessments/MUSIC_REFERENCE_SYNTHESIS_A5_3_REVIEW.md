# Music reference synthesis and fusion A5.3 review

## Candidate outcome

Music Studio can now ask Soul's configured local model to translate reviewed,
fallible reference evidence into an original composition target. Every whole or
component attempt is an immutable revision. Nothing becomes an approved source
until the Operator previews the exact revision digest and types
`APPROVE_MUSIC_REFERENCE_SYNTHESIS`.

Two to five approved targets can also be selected for one coherent fusion.
Soul receives only their approved derived packets under opaque source labels,
assigns each source a bounded role and normalized weight, and returns one new
target. Fusion does not concatenate prompts, generate audio, publish, queue
work, or approve itself.

## What was implemented

- One configured local-provider call per draft with a 90-second timeout, strict
  structured output, no tools, and no cloud fallback.
- Original target fields for intent, title, Sound and Structure, new lyrics with
  section markers, BPM, key, time signature, exclusions, and rationale.
- Whole-packet retry plus isolated retries for intent, title, Sound and
  Structure, lyrics, BPM, key, or time signature.
- Code-enforced byte-for-byte preservation of every unrequested field.
- Immutable `syn_` revisions, owner-private atomic writes, per-record file
  locks, stale-preview invalidation, and idempotent exact approval.
- Exact `REJECT_MUSIC_REFERENCE_SYNTHESIS` review that preserves rejected
  revisions, prevents their later approval, and permits a new retry.
- Source-name, source-title, imitation, soundalike, clone, and cover language
  rejection in stored target text.
- Explicit two-to-five selection for fusion; only approved selected track
  revisions are eligible.
- Fusion role coverage and positive weights that must sum to one.
- Fusion retries that preserve source roles and weights while isolating the
  requested target field.
- A Music Studio profile lens that visibly separates observed evidence from the
  proposed target and exposes only deliberate draft, retry, fusion, and approval
  controls.

## Files changed

- `lib/soul_core/music_reference_synthesis_service.rb`
- `lib/soul_core/music_reference_library_store.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-music-reference-synthesis-a5.rb`
- `scripts/eval-music-reference-synthesis-a5.rb`
- `docs/soul/MUSIC_REFERENCE_LIBRARY_AND_URL_INGESTION_DESIGN.md`
- `Makefile`
- this review artifact

## Commands and deterministic results

- `make verify-music-reference-synthesis` — passed all synthesis, retry,
  approval, stale-state, idempotence, fusion, and dashboard assertions.
- `ruby scripts/eval-music-reference-synthesis-a5.rb` — passed against the
  active `soul-local-chat` model after the bounded-output corrections described
  below; the final packet terminated `blocked_for_human_review`.
- `ruby scripts/verify-music-reference-library-a5.rb` — passed.
- `ruby scripts/verify-music-reference-analysis-a5.rb` — passed.
- `ruby scripts/verify-multi-model-music-studio-a0.rb` — passed.
- `ruby scripts/verify-music-studio-a1-setup.rb` — passed.
- `ruby scripts/verify-music-studio-a2.rb` — passed.
- `ruby scripts/verify-music-studio-a3.rb` — passed.
- `ruby scripts/verify-music-studio-a3-vocal-analysis.rb` — passed.
- `ruby scripts/verify-music-revision-draft.rb` — passed.
- `ruby scripts/verify-music-candidate-dispositions.rb` — passed.
- `ruby scripts/verify-structured-output-provider-contract.rb` — passed.
- `node --check assets/dashboard/dashboard.js` — passed.
- Ruby syntax checks for the store, service, facade, and verifier — passed.
- Dashboard service restart, active-state check, and loopback HTTP response —
  passed.
- `ruby scripts/verify-phase12b-in-process-application-api.rb` reached its
  repository-curation guard and stopped because this candidate contains
  intentionally untracked review files. No Phase 12B behavioral assertion
  failed before that expected pre-approval guard; rerun after approved staging.

## Local LLM eval

The active `soul-local-chat` model was evaluated with one synthetic reference
profile in a temporary directory. It received no source audio, transcript,
private memory, secret, cloud request, or real artist metadata. The final run
returned a complete original packet in roughly 15 seconds and terminated
`blocked_for_human_review`; it proposed “The Weight of Holding Still,” a 52 BPM
D-minor target with a substantial instrumentation/production/section brief,
new sectioned lyrics, exclusions, and rationale. No eval artifact persisted.

The live eval caught and drove repairs for three issues before the passing run:

- a 7,000-token ceiling allowed Mistral to continue until the 90-second read
  timeout, so the request is now strongly length-directed and capped at 3,500;
- oversized JSON-schema string repetition caused llama.cpp grammar rejection,
  so only parser-safe field bounds are expressed in the transport schema;
- unconstrained key/time fields and a too-short arrangement block produced
  verbose or generation-incompatible values, so compact key/time values and a
  substantive Sound and Structure block are now enforced.
- the first real PlayWarframe profile exposed an over-strict terminal-punctuation
  heuristic; the failed request stored no revision, and the heuristic was
  removed in favor of the provider finish reason, bounded request, and normal
  field-size validation.

This is behavioral evidence, not approval of creative quality. The first real
reference still needs Operator review for originality, usefulness, and musical
judgment.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Music reference records remain private Music Studio domain artifacts rather
  than a skill-private memory system.
- Lifecycle states touched: `complete`, `failed`, `awaiting_input`, and
  `blocked_for_human_review`.
- Every provider call returns a terminal result; there is no resident task,
  polling loop, queue, or background continuation.

## Risk classification

Moderate. Local model output can shape future composition inputs, but cannot
approve itself, generate audio, publish, invoke tools, use a cloud provider, or
change measured source evidence. Exact human approval is required for every
selected target revision.

## Known weaknesses

- The first live-model creative-quality evaluation remains outstanding.
- Because analysis-only mode intentionally retains no raw transcript or source
  audio, code can reject source titles/artists and imitation language but cannot
  compute lyric or melody similarity against the removed source. The local
  prompt forbids reconstruction and the Operator must review originality.
- Instrumentation and section evidence can be sparse when deterministic
  extraction cannot support those claims; the model is instructed to account
  for missing evidence rather than invent certainty.
- Fusion quality is model-dependent. Roles and weights provide reviewable
  structure, but musical coherence still requires human judgment.
- A5.4 still needs the explicit bridge that copies an approved target into a new
  composition brief and exposes the same flow conversationally through skills.

## Human review checklist

- [ ] Analyze one intended source and inspect the observed evidence plane.
- [ ] Draft the first complete target and verify it does not name or imitate the
  source.
- [ ] Retry one component and confirm every other displayed target field is
  unchanged.
- [ ] Reject one exact revision and confirm it remains visible as rejected and
  can be followed by a new retry.
- [ ] Preview and approve the exact selected revision.
- [ ] Approve a second profile, select both, and inspect fusion roles, weights,
  and coherent target.
- [ ] Confirm no audio generation or background continuation starts during any
  synthesis or fusion operation.
- [ ] Approve, request changes, or reject this candidate before commit.

## Human review outcome

```text
Outcome: approved
Reviewer: Operator
Date: 2026-07-17
Decision summary: Approved after live reference ingestion, synthesis review,
  exact rejection workflow, grounding corrections, and local-model validation.
Required changes: none
```
