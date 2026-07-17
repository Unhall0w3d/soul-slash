# Music Studio A3 vocal-analysis review

Status: candidate-complete; requires human review.

## Implemented

- Pinned, optional whisper.cpp v1.9.1 CPU runtime and `ggml-small.en.bin` manifest.
- The installer retains only `whisper-cli`, its GGML/Whisper libraries, and the
  license; upstream server, benchmark, quantizer, and test executables are not
  installed.
- Exact plan/confirmation installer with filename override restricted to manifest entries.
- Foreground candidate analysis with bounded process group, eight-thread cap, 360-second timeout, bounded output, and cleanup on terminal states or stream abandonment.
- Candidate-local transcript, timestamps, ordered lyric comparison, preserved revisions, and explicit human-authority routing.
- Music Studio preview/confirmation/progress surface, intended-versus-heard comparison, per-line evidence, visible rights status, and labeled 1–5 rating scale.
- Machine-heard segments render as lyric lines with stanza breaks inferred only
  from five-second-or-longer audio gaps; structural labels are not invented.
- BAD evidence exposes a deliberate revision-brief action that copies the
  immutable inputs into an editable form but performs no generation.

## Files changed

- `config/music_transcription_models.json`
- `scripts/soul-music-transcription`
- `lib/soul_core/music_candidate_analysis_service.rb`
- application contract, facade, dashboard HTTP transport, Music Studio HTML/JS/CSS, Makefile, verifier, brief, and this review artifact.

## Commands and results

- Official archive and model SHA-256/byte verification: passed.
- CPU pilot against the three-minute live candidate: passed in about 16 seconds.
- Live service analysis against `candidate_15f8fba3e320c36d`: terminal `blocked_for_human_review`; process exited; route `revision_recommended`.
- Deterministic vocal-analysis verifier: passed.
- Existing Music Studio A2 and A3 verifiers: passed.
- Phase 12C foreground-dashboard wrapper and earlier regressions: passed; it
  remains intentionally blocked only for the required human visual review.

## Local LLM eval

Not run. This slice performs deterministic ASR evidence extraction and does not ask a conversational LLM to decide routing, safety, or approval.

## Known weaknesses

- Singing ASR is fallible; backing vocals, effects, pronunciation, and arrangement can lower recall.
- The line matcher is an ordered heuristic, not forced alignment and not a rights/copyright comparison tool.
- English is the only pinned default model in this candidate.
- A revision attempt is routed but remains a separate Operator-triggered workflow; no automatic regeneration is included.

## Memory and lifecycle

- Shared memory keys added or used: none.
- Lifecycle states: `awaiting_input`, `failed`, `canceled`, `blocked_for_human_review`.
- Successful analysis intentionally remains `blocked_for_human_review`; only a human listening test can close the evidence gate.

## Risk classification

Local-state write and bounded CPU execution. No privilege, persistence, service, scheduler, external publication, or autonomous resource use.

## Human review checklist

- [ ] Preview clearly identifies CPU-only foreground behavior and exact candidate scope.
- [ ] Starting analysis requires the exact phrase.
- [ ] Progress is visible and the process exits after completion.
- [ ] Intended and machine-heard lyrics are readable side by side.
- [ ] Machine OK routes to human test; machine BAD routes to revision attempt.
- [ ] Neither route claims approval or rejection.
- [ ] The Operator can still record the independent human listening review.
