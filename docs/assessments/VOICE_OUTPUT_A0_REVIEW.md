# Voice Output A0 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Added explicit per-message `Speak` / `Stop` controls and a browser-local
curated voice selector to authenticated dashboard Chat. Each request runs
Supertonic 3 once on CPU, returns private non-cached WAV bytes, deletes
request-private inputs and outputs, and exits. Playback is owned by the browser
and is disposed at completion, Stop, transmission change, Chat exit, or
logout. The selected allowlisted voice applies per request without a service
restart or Core change.

## Files changed

```text
config/voice_synthesis_models.json
config/voice_synthesis_requirements.txt
lib/soul_core/voice_synthesis_service.rb
lib/soul_core/dashboard_http_application.rb
lib/soul_core/dashboard_command.rb
lib/soul_core/configuration_schema.rb
assets/dashboard/dashboard.js
assets/dashboard/dashboard.css
scripts/soul-voice-synthesis
scripts/soul-voice-synthesis-runner.py
scripts/verify-voice-synthesis-a0.rb
Makefile
.env.example
config/model_overrides.example.mk
README.md
docs/ARCHITECTURE.md
docs/CURRENT_STATE.md
docs/GETTING_STARTED.md
docs/guides/VOICE_INPUT.md
docs/guides/VOICE_OUTPUT.md
docs/soul/VOICE_OUTPUT_A0_BRIEF.md
```

## Commands and deterministic results

```text
Ruby syntax checks: pass
Python bytecode check: pass
node --check assets/dashboard/dashboard.js: pass
ruby bin/soul config validate: pass
make voice-synthesis-check: pass on reviewed host
make verify-voice-synthesis: pass
real F3 one-shot synthesis: pass; valid WAV; temporary directory removed
```

## Local voice evaluation

Supertonic 3 `F1`, `F3`, `F5`, `M1`, `M3`, and `M5` were rendered from
identical text at ten steps and 1.0 speed. Each approximately eleven-second
clip synthesized in about two seconds on the reviewed Ryzen 7 5800X CPU, with
roughly half a second of model-load overhead. The feminine tests passed the
Operator's initial quality review. `F3` remains the public default and `M3` is
the provisional masculine counterpart pending final human selection.

No local conversation-model eval was required. The feature reads an already
completed assistant message and does not change intent routing or response
generation.

## Memory keys

```text
Reads: none
Writes/updates: none
Forget behavior: request-private text/audio and browser object URL are disposed
```

## Lifecycle states touched

```text
complete
awaiting_input
failed
canceled (browser synthesis/playback abort)
blocked_for_human_review
```

## Risk classification

Class 3: authenticated local synthesis of conversation text.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
New listener added: no
Background polling added: no
Automatic narration added: no
GPU allocation added: no
Skill or confirmation gate weakened: no
Conversation or memory mutation added: no
```

## Known weaknesses

- Voice character is subjective and requires the Operator's final profile
  selection for the masculine counterpart.
- Speech begins after the complete WAV is synthesized; this slice is not
  streaming TTS.
- Aborting the browser request prevents playback, while the already-started
  server process remains bounded by its short request and 120-second timeout.
- Messages above 2,000 characters and JSON-shaped messages are not spoken.
- Pronunciation quality varies for code identifiers, acronyms, and unusual
  proper nouns.

## Playback compatibility correction

Live browser review found that synthesis completed with a valid PCM WAV, but
the dashboard's Content Security Policy rejected the request-private `blob:`
URL created for playback. The media directive now permits same-origin media
and browser-owned `blob:` media only. Script, image, connection, object, form,
frame, and base restrictions are unchanged. Deterministic coverage asserts
this exact playback requirement.

## Human review checklist

```text
[x] Confirm the feminine comparison clears the initial quality threshold.
[ ] Select M1, M3, or M5 after listening to the identical audition phrase.
[ ] Hot-swap between the curated feminine and masculine profiles without a restart.
[ ] Speak appears only on appropriate completed Soul messages.
[ ] Preparing and Stop states are visually understandable.
[ ] Stop ends playback immediately.
[ ] Changing transmissions or tabs stops playback.
[ ] Speech sounds natural enough for Soul's revised persona.
[ ] No voice process remains after synthesis.
```
