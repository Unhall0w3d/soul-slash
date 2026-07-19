# Music Vulkan 600-Second Qualification Review

Status: technical and human listening qualification passed; approved for production promotion

## Implemented

- Kept production Music Studio durations at 30, 90, and 180 seconds.
- Added a pilot-only 600-second duration guarded by `duration_600_v1`.
- Bound the duration and marker into the existing preview digest.
- Preserved one output, fixed inference settings, bounded execution, and the three-attempt LM collapse policy.
- Added a 600-second-only normalization for the LM's 3,001st terminal code, which otherwise exceeds the synthesizer's fixed 15,000-latent ceiling by six padded frames.
- Prepared one original Melodic Techno and Deep House instrumental request for technical and listening evaluation.

## Files changed

- `config/music_vulkan_models.json`
- `scripts/soul-music-vulkan-pilot`
- `scripts/verify-music-core-vulkan-feasibility.rb`
- `docs/soul/MUSIC_VULKAN_600_SECOND_QUALIFICATION_BRIEF.md`
- `docs/assessments/MUSIC_VULKAN_600_SECOND_QUALIFICATION_REVIEW.md`

## Commands and deterministic results

- `ruby -c scripts/soul-music-vulkan-pilot` — PASS
- `ruby -c scripts/verify-music-core-vulkan-feasibility.rb` — PASS
- `ruby scripts/verify-music-core-vulkan-feasibility.rb` — PASS (37 checks) after boundary repair.
- `git diff --check` — PASS
- First exact-gated 600-second execution — correctly stopped as `failed` before synthesis because 3,001 LM codes resolved to 15,006 latent frames against the pinned 15,000-frame ceiling.
- Second exact-gated 600-second execution — PASS; one excess terminal code was removed with explicit evidence and synthesis completed in 97.8 seconds.
- `ffprobe` artifact inspection — PASS; PCM 16-bit, 48 kHz stereo, exactly 600.0 seconds.
- `ffmpeg` level and silence inspection — PASS; mean -10.5 dB, peak 0.0 dBFS, no silence of two seconds or longer.
- `pgrep -af 'ace-(lm|synth)'` — PASS; no resident generation process.

## Pilot evidence

- First run: `20260719T052931Z-600s-61308e`
- LM plan: 3,001 audio codes for 600.2 seconds.
- Synthesizer refusal: `T=15006 exceeds silence_latent max 15000`; no WAV produced.
- Corrected run: `20260719T053305Z-600s-3de8c5`
- Output: PCM 16-bit WAV, 48 kHz stereo, exactly 600.0 seconds, 115,200,044 bytes.
- SHA-256: `d30d18be68ad01bd33bf3cfb95771d7be86c5b17feba610a21ad755bd161002e`
- Wall time: 97.8 seconds.
- Audio-code plan: 3,000 synthesis codes against 3,000 expected after one explicitly recorded terminal-code removal.
- Code diversity: 59.0% unique; 0.13% adjacent repeats; 0.53% dominant-code ratio; no deterministic collapse detected.
- Foreground release: no `ace-lm` or `ace-synth` process remained after completion.

## Local LLM evaluation

Not applicable. Duration authorization and audio-plan health are deterministic boundaries. The generated audio requires human listening review.

## Human listening evidence

The operator accepted the generated candidate as solid. The first minute was assessed as strong; accelerated review in 15-second increments found the composition remained coherent and developed perceptibly around 6:20. The lift was restrained rather than dramatic, but sufficient to demonstrate meaningful long-range movement without an obvious short-loop or global-plan collapse.

## Known weaknesses

- A valid waveform and diverse audio-code plan do not establish ten-minute musical coherence.
- A single long generation may repeat, drift from the requested genre, end poorly, or introduce unwanted voice-like material.
- This test does not compare a single ten-minute generation with a future arranged mix of shorter candidates.
- Qualification does not expose 600 seconds in project storage or the dashboard.

## Memory and lifecycle

- Memory keys added or used: none.
- Lifecycle states touched: `awaiting_input` and `blocked_for_human_review`; execution may additionally terminate `failed` or `canceled`.
- No persistent process is introduced.

## Risk classification

Local compute and temporary storage, medium.

## Human review checklist

- [x] Confirm the preview describes exactly one 600-second foreground pilot.
- [x] Authorize with the exact run phrase and digest.
- [x] Verify the output is 48 kHz stereo and approximately 600 seconds.
- [x] Listen for global-plan collapse, excessive short-loop repetition, unintended vocals, or silence.
- [x] Assess genre fit, motif continuity, transitions, harmonic development, late peak, and resolved ending.
- [x] Decide separately whether and how longer durations should enter Music Studio.

Decision: promote exactly 600 seconds as a fourth Music Studio preset. Do not authorize arbitrary lengths or promote the separate 210-second qualification.
