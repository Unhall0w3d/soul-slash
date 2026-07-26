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

Picture understanding currently requires **Daily Core** because the production
Gemma 4 model and its multimodal projector run there. If another Core is active,
the picture and draft remain selected; switch to Daily Core and send again.
Soul does not transfer Cores silently.

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
- PNG and JPEG are the only accepted formats in this slice.
- Animated images, SVG, PDF, URLs, camera capture, and continuous observation
  are unavailable.
- Screen understanding captures only one explicitly requested monitor, active
  window, or selected region and always previews it before analysis.
