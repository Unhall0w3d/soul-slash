# Voice Input A0 Brief

```text
date: 2026-07-24
human_authorization: approved in the active development conversation
implementation_authorized: yes
human_microphone_review_required: yes
risk: Class 4 - authenticated private audio upload and local transcription
```

## Objective

Add one explicit push-to-talk control to dashboard Chat. A bounded recording is
transcribed locally and inserted into the current composer as an editable
draft. It is never sent, interpreted, remembered, or used to invoke a skill
until the Operator presses Send.

## Authorized vertical slice

- Browser `getUserMedia` and `MediaRecorder` capture while Chat is visible.
- One authenticated, same-origin, CSRF-protected raw-audio route.
- WebM/Opus, MP4/AAC, Ogg/Opus, and WAV input containers.
- Eight MiB upload and sixty-second duration ceilings.
- `ffprobe` validation followed by FFmpeg 16 kHz mono PCM normalization.
- Existing pinned CPU-only whisper.cpp runtime and exact manifest model.
- Request-private temporary files removed at every terminal outcome.
- An editable transcript inserted at the current composer selection.
- Real listening and transcription states on the existing presence card.
- Public setup/check targets and documented `.env`/Makefile overrides.

## Lifecycle

```text
idle
-> explicit microphone click
-> browser permission
-> listening
-> explicit Stop or sixty-second ceiling
-> authenticated bounded upload
-> container and duration validation
-> CPU normalization
-> CPU transcription
-> complete / awaiting_input / failed / canceled
-> delete source, normalized audio, and raw recognition output
-> editable unsent composer draft
```

## Restraint and privacy boundary

- No wake word, always-listening mode, global hotkey, host capture process,
  daemon, new service, new listener, scheduler, queue, or background polling.
- Leaving Chat, closing the active conversation, or logging out stops and
  discards an active recording.
- No microphone device name or host path is committed.
- No raw audio, normalized audio, or machine transcription file is retained.
- The browser transcript remains ordinary unsent form state until Send.
- Speech does not bypass conversation intent classification, skill routing,
  Core requirements, destructive previews, or confirmation gates.
- The local model does not decide whether recording begins or whether the
  resulting text is sent.

## Portable dependency contract

Required host facilities:

```text
modern secure-context browser with getUserMedia and MediaRecorder
FFmpeg including ffprobe and WebM/MP4/Ogg/Opus/AAC decoding
pinned whisper.cpp runtime and one exact manifest-declared model
localhost, or reviewed HTTPS for LAN/mobile microphone permission
```

The reviewed default reuses `config/music_transcription_models.json`,
`ggml-small.en.bin`, and the user-local runtime root
`~/.local/share/soul/music/transcription`. Public clones may override the root,
manifest, and exact model filename. Unknown model filenames fail closed.

## Required evidence

- deterministic service success, timeout/failure, duration, MIME, and cleanup;
- authentication, Origin, CSRF, content-type, and upload-size enforcement;
- route-specific body allowance without widening the JSON API;
- visible and keyboard-operable recording state;
- mobile-responsive composer layout and reduced-motion behavior;
- no automatic composer submission;
- no persistence or new resident process;
- live human microphone test through the authenticated dashboard.
