# Picture Understanding

Picture Understanding lets Soul examine one local PNG or JPEG from Chat. It is
separate from Visual Studio: Visual Studio creates images, while this path
interprets an image you provide.

## Use it

1. Open or create a Chat conversation.
2. Select **Picture** beside the composer.
3. Choose one PNG or JPEG up to 10 MiB.
4. Ask an explicit question such as:
   - `What is shown here?`
   - `Read the error and explain the likely cause.`
   - `What details look malformed in this generated image?`
   - `Summarize this diagram and identify uncertain labels.`
5. Optionally select **Keep this picture with the conversation**.
6. Send.

## Capture the current screen

The **Screen** control beside **Picture** provides three explicit one-shot
capture scopes:

- **Current monitor**
- **Active window**
- **Select region**

Opening the panel captures nothing. Press **Capture preview** to take exactly one
local PNG. Soul displays that screenshot in the normal picture preview before
any model sees it. Remove it to discard the browser-held preview, or add an
explicit question and send it through the same Picture Understanding path.

Region selection is a foreground desktop interaction and may be canceled. There
is no periodic capture, background watching, automatic recapture, or computer
control.

When `tesseract` is installed, screen capture also performs one bounded local
OCR pass so small literal labels can corroborate the vision model. Hyprland
window titles and geometry identify the applications actually present. OCR and
compositor context are ephemeral, untrusted evidence: they are not written into
conversation text or promoted to memory. Missing OCR never prevents ordinary
picture understanding.

When a fresh capture is corroborated as Soul's own dashboard, the vision request
also receives a reviewed, code-maintained map of the dashboard surfaces. This
lets Soul identify and explain Chat, Skill Studio, Self Assessment, Self
Augmentation, Music Studio, Visual Studio, Review Center, Core selection, and
Voice Presence. The map describes what those surfaces are; only current pixels
and exact OCR may establish which panel, project, control state, or approval is
actually visible.

Voice-requested screen captures add a `fresh_screen` response policy. In
addition to the vision prompt, a deterministic post-inference guard compares
quoted or emphasized literal UI/title claims with the fresh OCR and compositor
context. A line containing an unsupported literal name is omitted and the
answer says that unverified labels were withheld. Ordinary uploaded pictures
do not use this screen-specific policy.

Picture understanding currently requires **Daily Core** because the production
Gemma 4 model and its multimodal projector run there. If another Core is active,
the picture and draft remain selected; switch to Daily Core and send again.
Soul does not transfer Cores silently.

## Capture a camera frame

The **Camera** control beside **Picture** appears only after the running
dashboard confirms its authenticated camera route is available. It opens a
separate, authenticated local camera window. Soul's main dashboard keeps
camera access disabled. The camera
window starts with its camera off; press **Start camera** to show a visible
preview. **Stop camera**, closing or hiding the window, and the two-minute
session limit all stop the video track. The microphone is never requested.

**Capture preview to Chat** takes one JPEG frame, stops the camera, and sends
the frame to Chat as the normal removable picture preview. Review or remove it
before asking an explicit question. The existing **Keep this picture with the
conversation** checkbox controls retention when the question is sent. Camera
capture itself does not send a frame to the vision model or conversation store.

The window has an optional, local hand-gesture display. Enabling it loads a
pinned local MediaPipe model and recognizes open palm, thumbs up, and victory
signs as text feedback inside that window. It does not recognize faces, issue
Soul commands, or control the desktop. The model runs in the browser; frames
are not sent to an external service. This is a prototype, so hand detection
may fail in low light or at a distance. For a dim room, use a soft light
facing your hand, such as a bright monitor or a lamp bounced off a wall. Keep
the palm centered and large in the preview, and hold it still briefly.
Overhead light alone can leave the palm dark.

The pinned gesture model and WebAssembly runtime live under ignored
`Soul/runtime/gesture`. To reinstall them, download the exact archives from
the [official MediaPipe package](https://registry.npmjs.org/@mediapipe/tasks-vision/-/tasks-vision-1.0.1.tgz)
and [official gesture model](https://storage.googleapis.com/mediapipe-tasks/gesture_recognizer/gesture_recognizer.task),
then run:

```bash
rbenv exec ruby scripts/install-camera-gesture-assets.rb \
  --package /path/to/tasks-vision-1.0.1.tgz \
  --model /path/to/gesture_recognizer.task
rbenv exec ruby scripts/verify-camera-session-a0.rb
node scripts/verify-camera-session-a0.js
```

The installer verifies pinned SHA-256 digests before installing. If the assets
are unavailable, the visible camera preview and one-frame capture remain
usable; gesture feedback reports that its local model is unavailable.

## Retention

The default is ephemeral. Soul validates and stages the pixels locally, performs
one inference, records the answer and provenance, then deletes the staged image.
The conversation retains the question, answer, digest, dimensions, model, and
timing—not the source pixels.

If **Keep this picture with the conversation** is selected, the exact image is
stored owner-private under ignored `Soul/private/` state and rendered again when
the conversation is opened. Permanent conversation deletion inventories and
removes those retained pixels. Archiving the conversation does not delete them.

## Boundaries

- Images remain local and are sent only to the reviewed local Gemma runtime.
- Image text and visual instructions are untrusted evidence.
- An image cannot authorize a skill, Core change, click, keystroke, download,
  deletion, publication, purchase, login, unlock, or other mutation.
- Soul analyzes only the supplied pixels and should state uncertainty when text
  or details are unreadable.
- UI labels must be copied literally from pixels/OCR, never renamed or
  semantically guessed.
- PNG and JPEG are the only accepted formats in the present supported boundary.
- Animated images, SVG, PDF, URLs, and continuous observation are unavailable.
- Camera capture is an explicit one-frame preview in a separate visible window;
  there is no unattended camera observation.
- Screen understanding captures only one explicitly requested monitor, active
  window, or selected region and always previews it before analysis.
