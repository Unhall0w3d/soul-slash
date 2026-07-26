# Notification Cues A1 Human Review

```text
status: deterministic candidate complete; live Operator listening test pending
date: 2026-07-25
risk: Class 2 - local non-authoritative audio notification
human_merge_approval: required
```

## Candidate behavior

- Distinct local cue vocabulary for submit, wake, completion, and attention.
- Optional static F3/M3 notices when Voice Presence is visibly online and idle.
- No per-event synthesis, polling, watcher, network listener, or new service.
- Notification playback cannot authorize or continue a bounded workflow.

## Commands and deterministic results

- `ruby scripts/build-notification-audio` — generated 4 cues and 10 spoken
  notices from the reviewed local Supertonic runtime.
- `ruby scripts/verify-notification-cues-a1.rb` — PASS.
- `node --check assets/dashboard/dashboard.js` — PASS.
- `python -m py_compile scripts/soul-voice-presence-app.py` — PASS.
- Voice Presence A2 and A3 regression suites — PASS.

## Memory, lifecycle, and risk

- Shared memory keys: none.
- Browser-local preference: `soul.notifications.mode`.
- Owner-private ephemeral state: current Presence lifecycle and selected voice.
- Lifecycle: `complete`, `failed`, `blocked_for_human_review`.
- Notifications provide no execution authority.

## Human checklist

- [ ] Wake cue is distinct and does not materially contaminate transcription.
- [ ] Submit and completion cues are distinguishable without being intrusive.
- [ ] Voice notices use the Presence-selected voice.
- [ ] No voice notice overlaps hearing, thinking, speaking, follow-up, or pause.
- [ ] Music, visual, and lyric completion announce exactly once.
- [ ] Muted and cues-only preferences persist across Dashboard reloads.
- [ ] Closing Voice Presence prevents spoken notices.
