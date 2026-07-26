# Notification Cues A1 Brief

## Human direction

Provide consistent notification sounds for Chat, wake listening, music
generation, visual generation, lyric transcription, and attention-required
outcomes. When the visible persistent Voice Presence interface is online,
optional voice notices should use pre-generated reusable phrases rather than
running synthesis for every event.

## Candidate scope

- Three local preferences: voice + cues, cues only, and muted.
- Distinct short nonverbal cues for submission, wake/listening, completion, and
  attention.
- Pre-generated F3 and M3 spoken notices for Chat, music, visual, lyric
  analysis, and attention events.
- Voice Presence publishes only its current visible lifecycle state and
  selected response voice to owner-private state.
- Dashboard voice notices require one authenticated point-in-time Presence
  status check and may play only while Presence is in idle `listening` state.
- Repeated events reuse static local WAV files. No event-time synthesis,
  listener, watcher, polling loop, daemon, or new service.
- Duplicate terminal notifications are suppressed within one browser session.

## Boundaries

- Notifications convey completion or attention, never authorization.
- A notification does not approve, retry, publish, promote, or mutate work.
- Browser autoplay policy may prevent playback until the Operator interacts
  with the page.
- Closing Voice Presence disables spoken notices; ordinary cues remain subject
  to the Dashboard preference.
- The slice terminates as `complete`, `failed`, or `blocked_for_human_review`.
