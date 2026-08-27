# Voice Presence A5 Wake Aliases Review

Status: accepted for current use; residual missed wakes retained for later tuning

## Implemented

- Raised both public phrases to 4.0 / 0.12 after the first live candidate
  produced no `Hey Soul` triggers and approximately 70% `Hey Slash` triggers.
- Added bounded unstressed-vowel variants and a conservative reduced-final-L
  `Hey Soul` variant at 3.0 / 0.18 for the Operator's pronunciation.
- Made runtime installation and validation derive the complete deterministic
  keyword file from the reviewed manifest.
- Updated the visible worker, application, launch-status contract, guide, and
  project tracker to expose both accepted phrases.
- Recorded the successful Memory A32 Voice semantic-recall acceptance without
  conflating it with the remaining wake-reliability review.

## Files changed

- `config/voice_presence_models.json`
- `scripts/soul-voice-presence-runtime`
- `scripts/soul-voice-presence-worker.py`
- `scripts/soul-voice-presence-app.py`
- `lib/soul_core/voice_presence_launch_service.rb`
- `scripts/verify-voice-presence-a2.rb`
- `scripts/verify-voice-presence-a4-local-latency.rb`
- `docs/soul/VOICE_PRESENCE_A5_WAKE_ALIASES_BRIEF.md`
- `docs/guides/VOICE_PRESENCE.md`
- `docs/assessments/MEMORY_SYSTEM_CLOSURE_A32_REVIEW.md`
- `docs/CURRENT_STATE.md`
- `config/project_tracker_seed.json`

## Lifecycle and memory

Both wake phrases retain the existing visible-window lifecycle and authorize
one ordinary conversation turn. No memory keys are added or used by this slice.
No wake audio, transcript, model listener, service, scheduler, or background
continuation is added.

## Risk and known weaknesses

Risk is low and local, but the lower public thresholds and additional exact
phoneme sequences can increase false wakes. The reduced-coda sequence is
intentionally less sensitive than either complete phrase. Static checks cannot
prove recognition for the Operator's voice or room acoustics. The installed
keyword file must be updated through the existing digest-bound installer before
the second live review.

## Commands and deterministic results

- `make verify-voice-presence` — passed: 35 A2, 14 A3, 40 A4, and 6
  notification-observer checks.
- `ruby -c scripts/soul-voice-presence-runtime` — passed.
- `ruby -c lib/soul_core/voice_presence_launch_service.rb` — passed.
- `python3 -m py_compile scripts/soul-voice-presence-worker.py
  scripts/soul-voice-presence-app.py` — passed.
- Project tracker JSON parse and `git diff --check` — passed.
- Installed sherpa-onnx model construction with a temporary exact two-keyword
  file — passed.
- `make voice-presence-check` — correctly blocked because the installed
  keyword file still contains the previous single phrase.
- `make voice-presence-plan` — revised candidate produced reviewed digest
  `32a3b3bffc9b62590ee1698fed198d67245ff5b2a6bd45bd438b6ae40a6ccde3`.
- `make voice-presence-check` after installation — complete, no runtime
  differences or missing host dependencies.

## Live acceptance

The revised five-sequence profile triggered reliably enough for ordinary use,
although it still missed some natural attempts. During the same review,
unrelated human speech played through the workstation speakers while Voice
Presence was listening and did not trigger a false wake. The Operator accepted
this balance for the current slice. Exact per-phrase rates were not recorded for
the revised profile, so this is practical acceptance rather than a quantitative
model benchmark.

## Human review checklist

- [x] Install and test the initial two-phrase candidate.
- [x] Record initial result: `Hey Soul` 0%; `Hey Slash` approximately 70%.
- [x] Install the revised reviewed keyword file through the exact plan/digest gate.
- [x] Restart the visible Voice Presence application.
- [x] Exercise both natural wake phrases and record that some misses remain.
- [x] Confirm unrelated speaker audio did not produce an obvious false wake.
- [x] Accept the current reliability/specificity balance for ordinary use.
