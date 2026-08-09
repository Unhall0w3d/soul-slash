# Unified Notification Lane A2 Brief

## Human direction

Extend Dashboard notifications so completed creative work, material improvement
reviews, fleet degradations, and backup/recovery outcomes use one clear,
local-only notification vocabulary while Voice Presence is visibly active.

## Candidate scope

- Four browser-local delivery modes: full voice, priority voice, cues only,
  and muted. Priority voice is the default for a new browser preference.
- Static, reusable F3 and M3 WAV notices for improvement review, recovery
  preparation, fleet attention, reboot-required, and backup attention.
- Serialized Dashboard playback and session-bounded exact-event deduplication.
- A silent fleet baseline: only later state degradations are announced.
- Existing Dashboard actions may emit review-ready or attention notices after
  their bounded operation completes. The exact Dashboard remains the detail
  surface.

## Boundaries

- No event-time synthesis, notification listener, watcher, timer, or new
  persistent service.
- Wazuh remains the separately accepted durable, high-priority exception.
- Notices never name devices, IP addresses, raw alerts, projects, or secrets.
- Notices never authorize, retry, publish, promote, maintain, reboot, or
  mutate anything.
- Recovery and ordinary successful backup operations are cues-only in Priority
  mode; material failures are eligible for spoken attention.
- Voice playback requires a fresh authenticated Voice Presence receipt in the
  `listening` state and does not interrupt an active voice interaction.

## Deferred

An owner-private outbox for Dashboard-closed notification delivery is deferred
for a separate, explicitly approved persistent-loop brief. No subsystem may
add its own timer or poller.
