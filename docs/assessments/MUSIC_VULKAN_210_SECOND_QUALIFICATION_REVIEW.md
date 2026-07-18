# Music Vulkan 210-Second Qualification Review

Status: technical qualification passed; human listening review pending

## Implemented

- Kept production Music Studio durations at 30, 90, and 180 seconds.
- Added a pilot-only 210-second duration guarded by the exact `duration_210_v1` request marker.
- Bound the qualification marker into the existing preview digest.
- Added deterministic coverage for qualified, unqualified, and improperly marked duration requests.
- Prepared an original instrumental stress-test request informed by general big-band Latin-funk ensemble characteristics.

## Files changed

- `config/music_vulkan_models.json`
- `scripts/soul-music-vulkan-pilot`
- `scripts/verify-music-core-vulkan-feasibility.rb`
- `docs/soul/MUSIC_VULKAN_210_SECOND_QUALIFICATION_BRIEF.md`
- `docs/assessments/MUSIC_VULKAN_210_SECOND_QUALIFICATION_REVIEW.md`

## Commands and deterministic results

- `ruby -c scripts/soul-music-vulkan-pilot` — PASS
- `ruby -c scripts/verify-music-core-vulkan-feasibility.rb` — PASS
- `ruby scripts/verify-music-core-vulkan-feasibility.rb` — PASS (33 checks)
- `ruby scripts/soul-music-vulkan-pilot plan --action run --request /tmp/soul-brass-meridian-210-request.json --manifest config/music_vulkan_models.json --root "$HOME/.local/share/soul/music"` — PASS; stopped at exact human gate
- exact-gated `RUN_MUSIC_VULKAN_PILOT` execution — PASS; first LM plan accepted, synthesis completed in 36.48 seconds
- `git diff --check` — PASS

## Pilot evidence

- Run: `20260718T210613Z-210s-5501aa`
- Output: PCM 16-bit WAV, 48 kHz stereo, 210.24 seconds, 40,366,124 bytes
- SHA-256: `dcc51dc9c99bb6906b85291d8f8589f9bf920be5184b3043ba8c36d843104f3f`
- Audio-code plan: 1,051 codes against 1,050 expected; 0.1% count delta
- Code diversity: 94.58% unique; 0.57% adjacent repeats; 0.67% dominant-code ratio
- Collapse guard: passed on attempt 1; no retry required
- Level inspection: mean -13.3 dB, peak 0.0 dBFS
- Silence inspection: no silence longer than one second before the ending; 3.525 seconds of ending silence
- Foreground release: no `ace-lm` or `ace-synth` process remained after completion

## Local LLM evaluation

Not applicable. Duration authorization and audio-plan health are deterministic boundaries. The generated audio requires human listening review.

## Known weaknesses

- A technically valid 210-second waveform may still be musically incoherent.
- Source-informed instrumentation does not guarantee the intended ensemble interaction.
- ACE-Step may add unwanted voice-like material despite an instrumental request.
- Qualification does not yet expose 210 seconds in project storage or the dashboard.

## Memory and lifecycle

- Memory keys added or used: none.
- Lifecycle states: `awaiting_input`, `blocked_for_human_review`, `complete`, `failed`, and `canceled` remain possible.
- No persistent process is introduced.

## Human review checklist

- [ ] Confirm the preview describes exactly one 210-second foreground pilot.
- [x] Authorize with the exact run phrase and digest.
- [x] Verify the output is 48 kHz stereo and approximately 210 seconds.
- [ ] Listen for global-plan collapse, excessive repetition, unintended vocals, or silence.
- [ ] Assess rhythm-section drive, distinct brass/reed roles, solo-to-ensemble transitions, late counterpoint, and final stinger.
- [ ] Decide separately whether 210 seconds should become a production duration.
