# Voice Presence Desktop Notification Observer A3 Review

## Candidate

Voice Presence can now opt into a short-lived child observer for the standard
desktop-notification D-Bus method while its visible window is open. It leaves
Noctalia as the session notification daemon and classifies a minimal first
cohort without retaining notification content.

## Files changed

- `scripts/soul-voice-presence-app.py`
- `scripts/soul_voice_notification_observer.py`
- `scripts/verify-voice-presence-notification-observer-a3.py`
- `scripts/build-notification-audio`
- `scripts/verify-notification-cues-a1.rb`
- `assets/notifications/f3-communication-urgent.wav`
- `assets/notifications/m3-communication-urgent.wav`
- `Makefile`
- `docs/soul/VOICE_PRESENCE_DESKTOP_NOTIFICATION_OBSERVER_A3_BRIEF.md`

## Verification

- `python3 scripts/verify-voice-presence-notification-observer-a3.py`
- `make verify-voice-presence verify-notification-cues verify-project-timeline`
- `python3 -m py_compile scripts/soul-voice-presence-app.py scripts/soul_voice_notification_observer.py`

## Lifecycle and risk

- Lifecycle: `complete` when enabled child starts; `failed` if the local
  monitor cannot start; `canceled` when the control is disabled or the visible
  app closes.
- Memory keys: none.
- Retention: no notification title/body/history/outbox; only an in-process
  metadata buffer that is discarded on message completion and child stop.
- Risk: Class 3. Local private metadata observation. It does not own or modify
  the D-Bus notification service and cannot act on notifications.

## Known weaknesses

- Some applications render native popup windows rather than standard D-Bus
  notifications; this candidate correctly does not claim to classify them.
- Browser-originated sites cannot safely be identified from app metadata in
  this slice and stay visual-only.

## Human review checklist

- [ ] Enable the observer in Voice Presence and confirm a normal test popup
  still arrives in Noctalia.
- [ ] Confirm Discord, Webex, Teams, and Steam show only an ephemeral class in
  Voice Presence and do not speak at normal urgency.
- [ ] Confirm a high-urgency recognized communication test plays one selected
  F3/M3 static phrase, then is locally cooldown-deduplicated.
- [ ] Confirm pausing, speaking, restart, toggle-off, and close never leave a
  monitor child running and never cause a spoken interruption.
