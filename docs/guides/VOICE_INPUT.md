# Voice Input

Soul's first voice surface is explicit push-to-talk inside dashboard Chat.
Starting and stopping that recording authorizes one bounded conversational
turn: local transcription, ordinary Chat submission, and one spoken Soul
reply. It does not treat microphone audio as authority for any skill gate.

## Requirements

- A current browser supporting `getUserMedia` and `MediaRecorder`.
- `ffmpeg` and `ffprobe` available on the dashboard host.
- Soul's pinned CPU transcription runtime and exact manifest model.
- `http://127.0.0.1`/`http://localhost`, or the reviewed Caddy HTTPS origin for
  LAN and mobile devices. Browsers normally refuse microphone access on an
  insecure LAN HTTP page.

Check the local host:

```bash
make voice-transcription-check
```

If the runtime is absent, inspect and execute the existing digest-bound install:

```bash
make voice-transcription-plan
make voice-transcription-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_MUSIC_TRANSCRIPTION
```

The default is whisper.cpp v1.9.1 with `ggml-small.en.bin`. It is shared with
Music Studio rather than downloaded twice. The command installs no service and
starts no resident process.

## Optional system-wide noise suppression

Soul supports the distribution package `noise-suppression-for-voice` through a
reviewed PipeWire RNNoise filter. This is not limited to Soul: the generated
**Soul Noise-Cancelled Microphone** becomes the user's default input for
browser Chat, Discord, Steam voice, Webex, and other applications.

After installing the host package, review and activate the current physical
microphone binding:

```bash
make voice-noise-filter-plan
make voice-noise-filter-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_RNNOISE_FILTER
make voice-noise-filter-check
```

Activation briefly restarts the existing PipeWire, PipeWire Pulse, and
WirePlumber user services. It creates no new service or resident process.
Applications that cache a microphone may need to select **Soul
Noise-Cancelled Microphone** once or restart.

## Operator flow

1. Open or create a Chat transmission.
2. Press **Speak** and grant microphone access if the browser asks.
3. Speak for no more than sixty seconds.
4. Press **Stop**. The sixty-second ceiling also stops capture.
5. Wait while Soul validates, normalizes, and transcribes locally.
6. Soul inserts the transcript, submits it through the ordinary Chat path,
   and produces one response.
7. The response is spoken with the currently selected Voice and Delivery
   profile. It remains visible with an explicit **Speak** control afterward.

Changing tabs, closing the conversation, or logging out during capture stops
and discards the recording.

## What is retained

```text
source recording: no
normalized WAV: no
whisper JSON: no
transcript: submitted once through ordinary Chat, then retained as message text
conversation message: one per completed push-to-talk action
```

The text follows the same conversation, memory, intent, skill, Core,
and confirmation rules as a typed message.

## Portable overrides

The normal public defaults require no `.env` additions. A different compatible
installation may set:

```dotenv
SOUL_VOICE_TRANSCRIPTION_ROOT=/absolute/user-local/runtime/root
SOUL_VOICE_TRANSCRIPTION_MANIFEST=/absolute/path/to/manifest.json
SOUL_VOICE_TRANSCRIPTION_MODEL=exact-model-filename-from-manifest.bin
```

For setup commands, put corresponding values in ignored `Makefile.local`:

```make
VOICE_TRANSCRIPTION_ROOT := /absolute/user-local/runtime/root
VOICE_TRANSCRIPTION_MANIFEST := /absolute/path/to/manifest.json
VOICE_TRANSCRIPTION_MODEL := exact-model-filename-from-manifest.bin
```

The manifest must bind the runtime release and model to exact byte counts and
SHA-256 digests. Supplying an arbitrary model filename alone is intentionally
unsupported.

## Present boundary

Speech output is documented separately in
[Voice Output](VOICE_OUTPUT.md). Voice Input still has no wake word, global
shortcut, headless capture, or always-available microphone session. Those
require separate privacy, activation, interruption, and lifecycle design.
