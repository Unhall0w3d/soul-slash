# Voice Input A0 Review

## Candidate status

```text
candidate_complete
```

## Implementation summary

Added explicit push-to-talk capture to authenticated dashboard Chat. One
bounded browser recording enters a dedicated raw-audio security boundary,
passes local FFmpeg validation/normalization and the existing pinned CPU
whisper.cpp runtime, and returns an editable unsent transcript. All temporary
audio and recognition files are deleted before the request returns.

## Files changed

```text
lib/soul_core/voice_transcription_service.rb
lib/soul_core/dashboard_http_application.rb
lib/soul_core/dashboard_server.rb
lib/soul_core/dashboard_command.rb
lib/soul_core/configuration_schema.rb
lib/soul_core/capability_matrix.rb
assets/dashboard/index.html
assets/dashboard/dashboard.js
assets/dashboard/dashboard.css
scripts/soul-voice-transcription
scripts/verify-voice-transcription-a0.rb
Makefile
.env.example
config/model_overrides.example.mk
README.md
docs/ARCHITECTURE.md
docs/CURRENT_STATE.md
docs/GETTING_STARTED.md
docs/guides/VOICE_INPUT.md
docs/soul/VOICE_INPUT_A0_BRIEF.md
```

## Commands and deterministic results

```text
ruby -c relevant Ruby files: pass
node --check assets/dashboard/dashboard.js: pass
ruby bin/soul config validate: pass
make voice-transcription-check: pass on reviewed host
make verify-voice-transcription: pass
```

The verifier covers service readiness, transcript shaping, duration and MIME
failure, request-private cleanup, authentication, same Origin, CSRF, content
type, route-specific upload limits, Permissions Policy, visible UI state,
editable/no-auto-send behavior, Chat-exit cancellation, and absence of
background behavior.

The live browser test exposed a MediaRecorder interoperability case: valid
WebM/Opus packets may carry no finite container-level duration. The service
now normalizes the bounded upload under a 60.25-second decode ceiling and
validates duration from the resulting PCM WAV. The regression verifier asserts
normalization occurs before duration inspection; malformed or excessive audio
still terminates without transcription or retention.

## Local LLM eval

Not run. Voice A0 stops at an editable composer draft and therefore does not
change the conversation model path or intent router. Spoken-language intent
variability will receive a separate behavioral evaluation after live
transcription evidence is available.

## Human microphone evidence

On 2026-07-24 the Operator confirmed that dashboard Chat visibly entered its
listening state, stopped when requested, closed the microphone path, and did
not send a message. This validates the intended two-step authority boundary:
voice capture/transcription can prepare text, while Send remains separate.

That A0 interaction was subsequently superseded by the separately authorized
Voice Conversation A1 slice, where the same explicit push-to-talk gesture
authorizes one ordinary Chat submission and one spoken reply.

## Memory keys

```text
Reads: none
Writes/updates: none
Forget behavior: temporary audio and raw transcription are removed at terminal return
```

## Lifecycle states touched

```text
complete
awaiting_input
failed
canceled (browser-visible capture cancellation)
blocked_for_human_review (missing or invalid runtime)
```

## Risk classification

Class 4: authenticated private audio upload and local transcription.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
New listener added: no
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
Raw audio retained: no
Transcript automatically sent: no
```

## Known weaknesses

- Recognition quality depends on microphone conditions, accent, phrasing, and
  the default English `small.en` model.
- The browser supplies no trustworthy word-confidence contract; Operator review
  is therefore mandatory by design.
- Capture is available only while the Chat page is open.
- Speech output is not included.

## Human review checklist

```text
[x] Speak/Stop control is visually clear in the reviewed browser.
[x] Browser permission and active-listening behavior are understandable.
[x] Stopping closes the microphone path visibly.
[x] No message is automatically sent.
[ ] Sixty-second cap and transcription status are visually reviewed.
[ ] Transcript accuracy/editability is reviewed with a spoken sentence.
[ ] Leaving Chat stops capture during a live recording.
[ ] Local transcription latency is acceptable.
[ ] No raw recording remains after completion or failure.
```
