# Voice Presence Desktop Notification Observer A3 Brief

> Historical contract: independent Notification Center A4-A6 moves this
> metadata-only classifier into a graphical-session service. Voice Presence no
> longer owns the observer; the privacy and no-action boundaries remain.

```text
date: 2026-08-09
human_authorization: explicitly approved in the active development conversation
implementation_authorized: yes
risk: Class 3 - local private desktop-notification metadata observation
```

## Objective

While the visible, Operator-launched Voice Presence window is open, offer an
opt-in way to classify a narrow first cohort of standard desktop notifications
without replacing, controlling, or storing Noctalia notifications.

## Authorized slice

- A `dbus-monitor` child exists only while the visible Voice Presence window
  has its **Observe desktop notifications** control enabled.
- It observes only standard `org.freedesktop.Notifications.Notify` method
  calls and ends immediately when the control is disabled, Voice Presence is
  restarted, or its window closes.
- It parses application identity and urgency metadata in memory. Notification
  title, body, action, image, and attachment content are never saved,
  displayed, logged, sent to Soul, or added to shared memory.
- Discord, Webex, Teams, and Steam receive visible, ephemeral classifications.
  Facebook/Messenger is explicitly suppressed. Unknown sources are visual-only.
- Only a recognized high-urgency communication source may play the selected
  static F3/M3 `communication-urgent` notice. It has a 90-second per-source
  cooldown and never interrupts hearing, thinking, speaking, or follow-up.

## Boundaries

- No D-Bus service ownership, proxy, replacement, interception, or alteration
  of Noctalia's notification daemon.
- No persistent service, watcher, systemd unit, scheduler, outbox, polling,
  notification history, or background continuation after window close.
- No notification content retention; the app's displayed classification is
  ephemeral and its source data is discarded as each D-Bus message completes.
- No skill invocation, Chat action, approval, Core transfer, external action,
  or automatic reply follows a desktop notification.
- Native Webex/Teams popup windows that do not use freedesktop D-Bus remain
  outside this slice and are explicitly not inferred from screen content.

## Lifecycle

```text
Voice Presence open + observer unchecked -> no monitor child
observer enabled -> one local D-Bus monitor child
recognized Notify metadata -> classify in memory -> optional static notice
observer unchecked / application restart / application close -> child stops -> buffers discarded
```

## Required evidence

- deterministic parser/classification checks prove no title/body reaches a
  result object;
- the existing Voice Presence verification proves the observer is owned by the
  visible application and uses a static phrase;
- live review confirms Noctalia still displays a standard test notification
  while the observer runs, normal Discord/Webex/Teams/Steam events remain
  visual-only, and one approved urgent test plays at most once per cooldown.
