# Voice Presence A2 Brief

```text
date: 2026-07-24
human_authorization: explicitly approved in the active development conversation
implementation_authorized: yes
persistent_microphone_authorized: only while the visible application is open
wake_phrase: Hey Soul
human_microphone_review_required: yes
risk: Class 4 - visible persistent local microphone capture and voice-originated Chat submission
```

## Objective

Provide a launchable desktop window that embodies Soul and acts as the
unambiguous on/off switch for persistent local voice. While the window is
open, an offline detector listens only for **Hey Soul**. One detection opens
one bounded spoken turn, routes the resulting text through Soul's ordinary
conversation substrate, and speaks the resulting reply. Closing the window
stops microphone capture and every child process.

The product direction is informed by visibly embodied broadcast companions
such as Y'allbot: state and personality should be legible without exposing a
technical console. Soul retains its own visual identity, privacy model,
authority boundaries, and local-first architecture.

## Authorized vertical slice

- One local PySide6 desktop window using Soul's reviewed masked and unmasked
  portrait assets.
- Explicit visible states: starting, listening, awakened, hearing, thinking,
  speaking, awaiting review, failed, and stopped.
- The window existing is the microphone-enabled state. Closing it disables
  persistent voice without requiring a reboot or stopping the dashboard.
- One resident CPU-only sherpa-onnx open-vocabulary keyword spotter while the
  window is open.
- The exact phrase `Hey Soul`, represented by a reviewed token file with
  conservative score and threshold defaults.
- Capture from the configured PipeWire source, defaulting to the existing
  `effect_output.soul-rnnoise` virtual microphone.
- After wake detection, one audible local cue followed by one utterance,
  bounded by speech-start, silence, and total-duration ceilings.
- Reuse the pinned whisper.cpp transcription service, ordinary application
  Chat router, conversation/skill/Core policy, and responsive Supertonic
  output service.
- One dedicated, durable **Voice presence** transmission so spoken turns are
  inspectable in the dashboard and continue naturally between window launches.
- A user-local desktop entry installed only through an exact digest and
  confirmation gate.
- Portable check, plan, install, launch, and verification commands.

## Interaction lifecycle

```text
application closed
-> Operator launches Soul Voice Presence
-> validate exact local runtime, model, assets, microphone, and dependencies
-> visible listening state
-> local "Hey Soul" detection
-> pause wake detection
-> play short local wake cue
-> wait at most 4 seconds for speech to begin
-> capture until 1.2 seconds of trailing silence or 30-second ceiling
-> local whisper.cpp transcription
-> ordinary chats.send request with interface voice_presence
-> complete / awaiting_input / blocked_for_human_review / failed / canceled
-> responsive local speech synthesis for eligible prose
-> local playback
-> delete request-private capture and response audio
-> return to listening
```

Closing the application at any point terminates capture, inference, synthesis,
and playback child processes, removes the private session directory, and
returns to `stopped`.

## Authority and conversational boundary

- A wake phrase authorizes one conversational turn. It is not authorization
  for a destructive, privileged, persistent, externally publishing, Core
  mutation, music/visual generation, or other gated action.
- Transcribed text enters exactly the same intent routing used by typed Chat.
- Conversation remains conversation; voice origin does not force a skill call.
- Read-only low-risk skills may retain their existing invocation policy.
- Protected actions return the existing preview or confirmation requirement
  and are spoken as an awaiting-review result.
- Soul may explain that a different Core is required, but voice presence does
  not invent or bypass Core authorization.
- The wake detector cannot submit text, call the model, or invoke a skill by
  itself. Only a completed bounded post-wake utterance can do so.

## Privacy and persistence boundary

```text
resident while window is open:
  PipeWire capture process
  sherpa-onnx keyword model
  visible desktop application

retained:
  text messages in the dedicated Voice presence transmission
  owner-private record containing only that canonical chat ID
  local application preference and installation receipts

never retained:
  continuous microphone audio
  wake audio
  command WAV after terminal return
  transcription JSON
  synthesized reply WAV after playback
```

There is no network speech provider, cloud wake-word service, wake-audio
training upload, hidden login service, systemd unit, scheduler, watcher, or
background process surviving application close.

## Bounded execution

- 160 ms detector model latency target.
- One CPU inference thread by default.
- Four-second speech-start timeout.
- Thirty-second utterance ceiling.
- 1.2-second trailing-silence endpoint.
- One active turn at a time; wake detection is suspended while hearing,
  thinking, or speaking.
- Existing transcription, Chat, Core, skill, and synthesis timeouts remain
  authoritative.
- Three consecutive terminal turn failures place the application in a visible
  paused state requiring an explicit **Resume listening** action.

## Portable dependency contract

Required host facilities are:

```text
Python with PySide6
uv
pw-record and pw-play from PipeWire
FFmpeg and ffprobe
the existing pinned whisper.cpp and Supertonic runtimes
an available local Soul conversation provider
```

The reviewed wake runtime pins sherpa-onnx, the exact upstream keyword model
archive, selected int8/fp32 model files, file sizes, and SHA-256 digests.
Public clones may override the user-local runtime root, exact manifest, source
node, wake score, and wake threshold. A plain-text `.env` override never
contains host audio.

## Required evidence

- deterministic lifecycle, threshold, endpoint, failure-count, cleanup, and
  child-termination tests;
- exact runtime/model/desktop-entry plan and install gate;
- verified `Hey Soul` tokenization with no custom cloud training;
- no model, wake detector, or transcript bypasses ordinary intent and
  confirmation policy;
- dedicated conversation creation and reuse;
- portrait and state transitions are accessible and reduced-motion aware;
- live false-wake, true-wake, transcription, response, speech, close, and
  relaunch review with the Operator.
