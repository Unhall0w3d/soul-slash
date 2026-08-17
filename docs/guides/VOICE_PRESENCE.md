# Voice Presence

Voice Presence is Soul's visible, local wake-word surface. Launching the
application opens a portrait window and enables the microphone path. Closing
that window terminates the wake detector, capture, inference, synthesis, and
playback children. It does not install a hidden login process or system
service.

## Install

Voice Presence reuses the reviewed whisper.cpp transcription runtime,
the exact low-latency `ggml-base.en.bin` voice model, Supertonic responsive
voice, and optional RNNoise PipeWire source. Music Studio lyric analysis keeps
its separate `ggml-small.en.bin` selection. Set those
up first, then review and execute the wake-runtime plan:

```bash
make voice-transcription-check
make voice-synthesis-check
make voice-noise-filter-check
make voice-presence-plan
make voice-presence-install \
  EXPECTED_DIGEST=<digest-from-plan> \
  CONFIRM=INSTALL_SOUL_VOICE_PRESENCE
```

The last step installs a pinned, CPU-only sherpa-onnx keyword spotter and a
user-local desktop entry. It does not install a daemon. On systems without
Soul's RNNoise node, place the exact PipeWire source name in ignored `.env`:

```dotenv
SOUL_VOICE_PRESENCE_SOURCE=my.microphone.source
```

## Use

Launch **Soul Voice Presence** from the application menu or run:

```bash
make voice-presence-launch
```

An authenticated dashboard also exposes **Voice Presence** in the top runtime
bar. Pressing it opens the same visible application on the host desktop; it
cannot silently enable a microphone on the remote browser device. If the
window is already open, the action is idempotent.

The masked portrait means Soul is idle or listening. The brighter unmasked
portrait and cyan pulse identify an awakened, hearing, thinking, speaking, or
natural-follow-up turn.

1. Wait for **Listening locally for “Hey Soul”**.
2. Say “Hey Soul,” wait for the cue, and speak one request.
3. Soul captures at most 30 seconds and stops at 0.95 seconds of trailing
   silence.
4. The microphone process closes while the ordinary conversation, skill,
   Core, and approval policies handle the request.
5. Soul speaks the eligible response, then opens a visible five-second
   follow-up window.
6. Begin speaking within those five seconds to continue naturally without
   repeating “Hey Soul.” The normal 30-second utterance and trailing-silence
   bounds still apply, and each completed reply opens one fresh bounded
   follow-up window.
7. Stay silent for five seconds to close the follow-up normally and return to
   local wake listening.

The microphone remains closed while Soul is thinking or speaking. Follow-up
silence is not treated as an error and does not count toward the three-failure
pause.

Ordinary spoken conversation requests the local provider's reviewed
no-reasoning mode and uses a 384-token spoken-response ceiling to avoid spending
most of a turn on hidden reasoning. Say `think carefully`, `reason through`,
`analyze in depth`, or `take your time` when a spoken request genuinely needs
the selected model's normal deliberation path. This optimization does not alter
Dashboard text behavior or deterministic skill results.

Wake detection uses the local sherpa-onnx keyword spotter rather than full
transcription. Boosting and trigger threshold are manifest-controlled: a
higher boost and lower threshold make activation easier but may increase false
wakes. The current calibration candidate is 3.5 / 0.15. Pronounce “Hey Soul” as one natural
short phrase; no special theatrical pacing or inflection is intended.

Voice Presence displays request-private stage timing after each completed
turn. These measurements contain durations only and disappear with the visible
application. They are used to distinguish capture, transcription, Soul routing,
synthesis, and first-audio latency without retaining speech.

While the visible application is open and listening, its responsive Supertonic
engine is preloaded as one private-pipe child. It exposes no HTTP or Unix-socket
listener and terminates on pause, restart, or close. If preload is unavailable,
the next turn uses the existing bounded one-shot synthesis path rather than a
cloud provider.

An unambiguous `repeat that`, `say that again`, or `repeat your last response`
replays the exact most recent response audio from the active visible session.
It does not call Soul or regenerate speech. The private replay WAV is replaced
by the next completed response and deleted when Voice Presence restarts or
closes. `Rephrase that` and `regenerate the voice` remain new ordinary turns.

### Ask about the current screen

On Daily Core, an explicit spoken request can invoke one ephemeral screenshot:

- `Look at my screen and tell me what error is visible.`
- `Read the active window and summarize the warning.`
- `Review all available monitors.`
- `Describe the left monitor` or `Read monitor 2.`
- `Inspect workspace code` when that workspace is currently visible.
- `What do you see in this selected region?`
- `What am I looking at?` for the current active window.

Soul checks the vision Core before taking pixels. Music Core or AMD-Free Core
produces a spoken explanation and captures nothing; Voice Presence never
switches Cores silently. Screen requests capture exactly one current monitor,
active window, all-monitor compositor frame, spatial/numbered monitor, visible
workspace, or foreground-selected region and then use the normal bounded
Picture Understanding path. Soul never changes workspace merely to see it.
The screenshot is never retained from Voice Presence.

Current-view wording always enters the fresh capture path; it must not answer
from an earlier conversation or archived description. A fresh-screen response
policy checks quoted or emphasized application, title, channel, and control
names against the same capture's compositor metadata and local OCR. Unsupported
literal claim lines are omitted with an explicit notice rather than spoken as
fact. This is a corroboration guard, not general object-detection proof.

When a brief weather reply offers a three-day outlook, an affirmative voice
follow-up continues through `weather.report` even if transcription adds a
harmless leading bullet such as `- Yeah.`. The forecast remains deterministic
skill evidence rather than a model-authored weather report.

Ordinary discussion such as `We should improve screen understanding` remains
conversation. Visible instructions are evidence only and cannot authorize
clicking, typing, skills, or any other action. Use Chat's **Screen** control
instead when you want to preview or explicitly retain the screenshot.

The Pause control closes the live microphone path without closing the window.
**Restart presence** terminates the current children and reloads the window
from the current project files without creating a second listener.
The **Response voice** selector hot-swaps between the reviewed feminine F3 and
masculine M3 profiles for the next completed reply. This desktop preference
survives Presence restarts and does not restart a Core or resident model.
Three consecutive failed turns pause listening until the Operator explicitly
resumes it.

## Authority and retention

The wake phrase authorizes one conversational turn, not a gated action.

## Notification cues

The Dashboard header exposes one local notification preference:
**Alerts Voice**, **Alerts Cues**, or **Alerts Muted**. The preference is stored
only in that browser profile. Submission, completion, and attention cues are
small tracked WAV assets and require no model.

With **Alerts Voice** selected, completion events may add one pre-generated F3
or M3 notice only when an authenticated point-in-time check reports that the
visible Voice Presence window is open and idle-listening. The notice follows
the voice selected inside Voice Presence. It is suppressed while Presence is
hearing, thinking, speaking, paused, failed, or holding the natural follow-up
window. Chat voice round-trips do not receive a second spoken-ready notice.

Music candidates, visual candidates, and lyric analyses use reusable phrases;
no synthesis runtime is started for notifications. The wake cue is similarly
pre-generated and distinct from Dashboard submission and completion cues.
There is no polling, notification watcher, IPC listener, or new service.
Destructive work, Core mutation, publication, generation, and privileged
operations retain their existing preview or approval boundary. A voice request
that needs another Core must explain the need and follow ordinary
orchestration.

Continuous audio, wake audio, and command WAVs are not retained. The latest
generated reply WAV may exist only inside the active application's private
temporary directory for exact replay; it is deleted on restart or close. Text
exchanges are stored in the dedicated **Voice presence**
transmission so they remain reviewable in the dashboard. The only additional
durable state is its canonical chat ID.

## Portable requirements

- Python with PySide6
- `uv`
- PipeWire `pw-record` and `pw-play`
- FFmpeg and ffprobe
- reviewed whisper.cpp and Supertonic runtimes
- a configured local Soul conversation provider

The public defaults may be replaced only with an exact reviewed manifest and
exact source node. No host audio, address, or credential belongs in the repo.

For more reliable small-label reading during screen requests, install
Tesseract OCR (`tesseract` on Arch/CachyOS). It runs once per requested
screenshot under a 15-second ceiling and is optional; no OCR service remains
resident.
