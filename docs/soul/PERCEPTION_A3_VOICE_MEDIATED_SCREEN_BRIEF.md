# Perception A3 - Voice-Mediated One-Shot Screen Brief

## Purpose

Let the visible Voice Presence application carry one unmistakable spoken
request for current-screen understanding through the existing A2 capture and A1
picture-analysis paths.

A3 changes transport, not authority. It does not add continuous vision,
computer control, automatic Core transfer, or a general “Soul can see” claim.

## Invocation contract

A request must contain both:

1. an explicit perception verb or question, such as `look at`, `inspect`,
   `analyze`, `read`, `describe`, `examine`, `what is on`, or `what do you see`;
2. an explicit current target:
   - `my screen`, `current screen`, or `monitor`;
   - `current window`, `active window`, or `this window`;
   - `all monitors`, `left monitor`, `right monitor`, or `monitor 1/2`;
   - a current or specifically named/numbered visible workspace;
   - `selected region`, `screen region`, or `this area`.

Examples that invoke:

- `Look at my screen and tell me what error is visible.`
- `Read the active window and summarize the warning.`
- `Review all available monitors and summarize what is open.`
- `Describe monitor 2.`
- `Read workspace code.`
- `What do you see in this selected region?`

Examples that remain conversation:

- `We should improve screen understanding.`
- `I spend too much time looking at screens.`
- `Tell me how screen capture works.`
- `Can you build a skill that watches my screen?`

The parser is deterministic. The language model does not decide whether capture
authority exists.

## Core and capture behavior

- A3 checks the reviewed local vision provider before capture.
- Daily Core proceeds.
- AMD-Free Core or Music Core returns a spoken `awaiting_input` explanation
  without capturing pixels or switching Cores.
- `screen` resolves the currently focused monitor.
- `window` resolves Hyprland's current active-window geometry; with the
  Operator's `follow_mouse=1` configuration this is the window under the
  pointer.
- all-monitor capture uses one compositor frame containing all outputs.
- left/right and monitor numbers resolve by compositor position from left to
  right.
- a workspace resolves only when it is currently visible on a monitor. A3
  never changes workspaces to obtain a screenshot.
- `region` opens one foreground `slurp` selection that may be canceled.
- A successful capture immediately enters the existing ephemeral A1 picture
  path with the exact transcript as the question.
- When available, one bounded Tesseract pass supplies ephemeral literal-text
  corroboration and Hyprland supplies the titles and geometry of windows
  actually present in the captured target. Neither supplement is retained or
  treated as instruction.
- If the pixels and OCR identify `LOCAL VOICE PRESENCE` and `Soul /`, the
  vision path may identify Soul's own reviewed Voice Presence surface and its
  exact controls. It must not rename or semantically reinterpret UI labels.

There is no durable screenshot preview in the Voice Presence window. For that
reason A3 is narrower than Dashboard A2: the exact spoken request is the
capture action, the portrait/status visibly changes to capture/inspection, and
pixels are never retained. Operators who want preview or retention use Chat's
Screen control.

## Conversation and speech behavior

- The dedicated Voice Presence transmission records the user request and
  resulting answer or terminal explanation.
- A completed observation is spoken through the selected responsive voice.
- `awaiting_input`, `canceled`, and safe failure explanations may also be
  spoken, then Voice Presence returns to listening.
- Screenshot content remains untrusted evidence and cannot invoke another skill
  or authorize any mutation.

## Bounded execution

A3 inherits:

- A2 one-capture, byte, pixel, geometry, selection, command, and cleanup bounds;
- A1 local-only provider, inference timeout, output, retention, and evidence
  bounds;
- Voice Presence one-turn, failure-count, child-process, and close-window
  bounds.

No new resident process, service, watcher, scheduled task, or polling loop is
added.

## Acceptance

- exact screen, active-window, and region requests route correctly;
- refresh/update-view phrasing and visible-text requests force a new capture
  rather than allowing the chat model to reuse an old description;
- all, left/right, numbered-monitor, and visible-workspace targets resolve
  deterministically without changing compositor state;
- conversational mentions do not route;
- missing explicit target or perception intent does not route;
- non-Daily Core captures nothing and returns `awaiting_input`;
- successful capture uses A2 then A1 exactly once;
- source pixels remain ephemeral;
- OCR and compositor context are bounded, ephemeral, and absent from stored
  conversation text;
- canceled selection is terminal and spoken;
- one user/assistant exchange is retained;
- visible screenshot instructions cannot invoke a skill or control action;
- Voice Presence still handles ordinary conversation through `chats.send`;
- all A1, A2, Voice Presence, weather, and conversational routing regressions
  remain green.
