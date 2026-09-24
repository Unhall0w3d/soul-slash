# Unattended Whisper verification — 2026-09-24

The Operator reported Elden Ring closed and authorized unattended Whisper
verification, followed by commit and merge. No live microphone was opened and
no new voice recording was made. The retained synthetic `question.wav` and
`followup.wav` were used through Soul's routed transcription service and the
already selected Soul-Lite Core. No Core transition or service deployment was
needed.

## Fresh admission and result

- No Elden Ring process was observed. The AMD advisory gate passed with
  15,246,565,376 bytes free against a 4 GiB minimum. This is a point-in-time
  observation, not an OS-wide GPU reservation.
- Effective Core status before and after was `amd-free` (Soul-Lite), with
  `nvidia-fallback` active. The routed Whisper check reported the pinned
  `whisper.cpp-vulkan` candidate available on RX 6900 XT.
- Both retained clips transcribed successfully: “What happens if the original
  path already exists?” and “Could you explain that in a little more detail?”
  The AMD transaction receipts reported `restored: true`, Vulkan0 recognition,
  no borrowed chat runtimes, and bounded recovery. Full ASR took 8.748 and
  8.194 seconds respectively; CLI recognition took 1.512 and 0.964 seconds.
- The native CLI invoked with invalid `--device 99` exited 3 and emitted
  `required GPU unavailable; refusing CPU fallback`. This proves the tested
  binary rejected that unavailable device. The candidate `libwhisper.so.1.9.1`
  and CLI hashes matched their source-curation pins before testing.
- Postflight Core status remained `amd-free`, with zero active model leases,
  no pending handoff file, and the AMD advisory gate again reporting
  15,246,565,376 bytes free.

Private runtime evidence is under
`Soul/runtime/qualification/amd-live-nvidia-20260924-2203439-9hd3xx/`.
The fixture model replies are not policy evidence: one suggested a silent
failure or automatic rename, neither of which was established by this test.
The observed transcripts and runtime receipts qualify speech recognition and
handoff, not Soul's file-restoration behavior or conversational fidelity.

## Deterministic checks

`verify-amd-voice-transcription.rb`, `verify-routed-voice-transcription.rb`,
`verify-amd-whisper-handoff.rb` (90 checks plus a fixed-clock bound),
`make verify-crucible-network-syslog`, and
`python3 -I scripts/verify-restricted-config-capture.py` all passed.
The earlier isolated Vulkan build of the pinned whisper.cpp source and
seven-line GPU-required patch is recorded in
`VOICE_MODEL_RUNTIME_SOURCE_CURATION_20260923.md`; this check used the
already pinned installed candidate, not the temporary rebuilt binary.

Attended browser microphone, wake-word, and Voice Presence semantic-memory
acceptance remain separate human tests. No memory or conversation projection
was rebuilt by this unattended test.
