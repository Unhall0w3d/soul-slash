# Perception A2 - One-Shot Screen Understanding Brief

## Purpose

Allow the Operator to explicitly capture one current monitor, active window, or
selected region, preview the immutable screenshot in Chat, and ask Soul one
bounded question through the already reviewed Picture Understanding path.

A2 is not observation. It is a foreground capture initiated by one deliberate
button press. Soul never watches, periodically samples, automatically recaptures,
or acts on visible controls.

## Approved surface

Chat exposes a **Screen** control beside **Picture**. Opening it presents three
capture scopes:

- **Current monitor** — the currently focused Hyprland monitor, resolved at the
  moment the preview is requested.
- **Active window** — the exact current Hyprland active-window geometry,
  resolved at the moment the preview is requested.
- **Select region** — one foreground `slurp` selection followed by one `grim`
  capture of the returned geometry.

The captured PNG is displayed in the existing attachment preview before any
model inference. The Operator may remove it, change the question, or send it
through the existing Daily-Core picture path. Capture alone never appends a
message or invokes a model.

## Host and dependency boundary

A2 uses only the existing local Hyprland tools:

- `hyprctl -j monitors`
- `hyprctl -j activewindow`
- `slurp`
- `grim`

Commands are executed as argument arrays without a shell. Monitor names and
geometry are resolved from structured Hyprland output and validated before use.
The service refuses unsupported compositors or missing tools rather than adding
packages or changing the desktop.

## Privacy and retention

- A capture is staged in owner-private ignored state.
- The service validates PNG signature, dimensions, pixel count, and byte size.
- Staged files are removed before the capture request returns.
- The browser holds the preview only until it is removed, replaced, sent, or the
  page is reloaded.
- Sending defaults to the existing ephemeral Picture Understanding behavior.
- The existing **Keep this picture with the conversation** checkbox is the only
  durable pixel-retention choice.
- Screenshots never enter Soul Vault or memory automatically.

## Authority boundary

Everything visible in a screenshot is untrusted evidence. It cannot authorize:

- clicks, typing, keystrokes, downloads, uploads, login, unlock, or navigation;
- a skill, Core transfer, model load, file mutation, deletion, or publication;
- any claim about state outside the supplied pixels.

A2 adds no computer-control surface. Soul may describe or troubleshoot the
capture, but it cannot interact with it.

## Bounded execution

- one capture per request;
- at most 10 MiB, 12,000 pixels per dimension, and 48 million pixels;
- 30-second capture timeout for monitor and active-window captures;
- 120-second foreground timeout for region selection and capture;
- timed-out child processes are terminated and reaped;
- no process, watcher, or worker remains after return.

Terminal states are:

- `complete`
- `failed`
- `canceled`
- `awaiting_input`
- `blocked_for_human_review`

## Acceptance

Deterministic verification must cover:

- exact focused-monitor resolution;
- exact active-window geometry resolution;
- selected-region geometry validation;
- invalid or empty compositor output;
- missing dependency;
- canceled region selection;
- command timeout and process cleanup;
- PNG size and dimension limits;
- staging cleanup;
- authenticated same-origin/CSRF route;
- preview before inference;
- reuse of the existing picture-analysis path;
- absence of periodic capture, screen polling, and computer-control calls.

Human review must confirm that a capture is never taken merely by opening the
menu and that the preview can be removed without invoking Gemma.
