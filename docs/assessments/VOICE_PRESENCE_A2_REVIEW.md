# Voice Presence A2 Human Review

```text
status: deterministic candidate complete; live Operator validation deferred and untested
date: 2026-07-24
risk: Class 4 - visible persistent microphone capture and voice-originated Chat submission
human_merge_approval: required
```

## Implemented

> **Live validation:** Untested after the 2026-07-25 wake-sensitivity
> installation. Revisit missed wakes, false wakes, ordinary pacing, and
> foreground-media/noise behavior when the Operator is back at the computer.

- Visible PySide6 Soul Voice Presence application whose window is the local
  microphone consent boundary.
- Masked idle/listening and brighter unmasked awakened/hearing/thinking/
  speaking portrait states with a reduced-content cyan pulse.
- Offline CPU-only sherpa-onnx open-vocabulary recognition of **Hey Soul**.
- Reviewed wake sensitivity uses a 2.0 keyword boost and 0.25 trigger threshold;
  the lower threshold makes triggering easier while preserving the visible
  window and three-failure bounds.
- Existing RNNoise PipeWire virtual microphone as the portable default source.
- One bounded post-wake utterance with four-second speech-start, 30-second
  total, and 1.2-second trailing-silence ceilings.
- Microphone process stopped while Soul thinks and speaks.
- Existing whisper.cpp transcription, ordinary application Chat interface,
  conversation/skill/Core policy, and responsive Supertonic speech path.
- Dedicated dashboard-reviewable **Voice presence** transmission.
- Three-failure pause and explicit resume.
- Exact digest-bound runtime/model installation and user-local desktop entry.
- Authenticated, same-origin, CSRF-protected dashboard launch with an
  idempotent single-instance lock.
- In-window restart that replaces the current process and reloads project
  changes without opening a second listener.
- Persisted in-window selection between the reviewed F3 feminine and M3
  masculine responsive voices, applied to the next completed turn.
- Child termination and request-private audio cleanup on window close.

## Files changed

- `config/voice_presence_models.json`
- `config/voice_presence_requirements.txt`
- `scripts/soul-voice-presence`
- `scripts/soul-voice-presence-app.py`
- `scripts/soul-voice-presence-worker.py`
- `scripts/soul-voice-presence-bridge`
- `scripts/soul-voice-presence-runtime`
- `scripts/verify-voice-presence-a2.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/voice_presence_launch_service.rb`
- `lib/soul_core/voice_transcription_service.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `Makefile`
- `.env.example`
- `config/model_overrides.example.mk`
- `README.md`
- `docs/GETTING_STARTED.md`
- `docs/CURRENT_STATE.md`
- `docs/guides/VOICE_PRESENCE.md`
- `docs/soul/VOICE_PRESENCE_A2_BRIEF.md`

## Commands and deterministic evidence

```text
ruby scripts/verify-voice-presence-a2.rb
  complete; 32 checks

ruby scripts/verify-voice-transcription-a0.rb
  passed

ruby scripts/verify-voice-synthesis-a0.rb
  passed

ruby scripts/verify-voice-synthesis-a1-expressive.rb
  passed

ruby scripts/verify-voice-noise-filter-a1.rb
  passed

make voice-presence-check
  complete; exact runtime/model/keyword assets valid

bounded worker microphone smoke test
  loaded model, opened effect_output.soul-rnnoise, entered listening,
  terminated cleanly at timeout

retained native-WAV end-to-end replay
  transcribed “What's the weather like today?”, completed an ordinary Chat
  response, and rendered a valid 13.9-second 44.1 kHz mono response WAV

in-window restart
  AT-SPI invoked the reviewed control; application PID and window identity
  changed while the single-instance lock remained held

git diff --check
  passed
```

The first install attempt failed safely because the reviewed release name did
not include the archive's `sherpa-onnx-` directory prefix. The partial install
was removed. `archive_root` was added to the exact manifest and the new plan
installed successfully.

## Local LLM evaluation

No separate LLM eval was added. Voice text enters the already-reviewed
ordinary conversation runtime; this slice changes transport and visible
lifecycle, not routing semantics or safety authority.

## Memory and durable state

- No memory keys added.
- One owner-private continuity receipt stores only the canonical Voice
  presence chat ID.
- Spoken user and assistant text are retained through the existing canonical
  Chat store.
- Continuous audio, wake audio, command WAV, transcription JSON, and response
  WAV are not retained.

## Lifecycle states

```text
starting
listening
awakened
hearing
thinking
speaking
paused
complete
awaiting_input
blocked_for_human_review
failed
canceled
stopped
```

## Known weaknesses

- Wake sensitivity still needs live false-wake and missed-wake calibration in
  the actual room. The first live pass found the original 1.5/0.30 setting too
  conservative and staged the reviewed 2.0/0.25 adjustment.
- This is half-duplex. It does not support barge-in while Soul is speaking.
- Spoken replies use the responsive voice path; expressive voice remains an
  explicit, more resource-intensive path.
- Desktop size and placement remain compositor-controlled.
- Wake language is English in this candidate.
- Voice and typed chat share the same deterministic intent router. Natural
  weather questions now invoke the existing read-only `weather.report` skill;
  the local model no longer decides whether that registered capability exists.

## Human review checklist

- [ ] “Hey Soul” wakes reliably at normal speaking volume.
- [ ] Nearby conversation and media do not create frequent false wakes.
- [ ] The cue is audible and does not become captured speech.
- [ ] A complete utterance transcribes rather than losing its beginning.
- [ ] The dedicated Voice presence transmission appears in Chat.
- [ ] A conversational request stays conversational.
- [ ] A gated request does not bypass its preview/confirmation boundary.
- [ ] Soul's reply plays once and listening resumes.
- [ ] Pause closes the microphone path.
- [ ] Closing the window leaves no wake, capture, bridge, or playback process.
- [ ] Relaunch reuses the dedicated transmission.
