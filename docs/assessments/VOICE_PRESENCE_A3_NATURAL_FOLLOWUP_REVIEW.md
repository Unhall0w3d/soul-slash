# Voice Presence A3 Natural Follow-Up Human Review

```text
status: deterministic candidate complete; live Operator validation deferred and untested
date: 2026-07-25
risk: Class 4 - visible bounded microphone capture and voice-originated Chat submission
human_merge_approval: required
```

## Implemented

> **Live validation:** Untested. Revisit the five-second response window,
> same-transmission continuity, repeated follow-ups, silent expiry, and gated
> follow-up authority when the Operator is back at the computer.

- A visible five-second speech-start window after each completed spoken Soul
  response.
- Natural follow-up submission without repeating the wake phrase.
- Existing 30-second utterance and 1.2-second trailing-silence limits retained
  after speech begins.
- A fresh five-second window after each completed follow-up response.
- Normal, non-failing expiry back to local wake-word listening.
- Microphone capture remains stopped while Soul thinks and speaks.
- Existing pause, restart, close, cleanup, three-failure, Core, skill, and
  approval behavior retained.

## Files changed

- `config/voice_presence_models.json`
- `scripts/soul-voice-presence-worker.py`
- `scripts/soul-voice-presence-app.py`
- `scripts/verify-voice-presence-a2.rb`
- `scripts/verify-voice-presence-a3.rb`
- `scripts/verify-voice-transcription-a0.rb`
- `Makefile`
- `README.md`
- `docs/CURRENT_STATE.md`
- `docs/guides/VOICE_PRESENCE.md`
- `docs/soul/VOICE_PRESENCE_A3_NATURAL_FOLLOWUP_BRIEF.md`

## Commands and deterministic evidence

```text
ruby scripts/verify-voice-presence-a3.rb
  complete; 14 checks

ruby scripts/verify-voice-presence-a2.rb
  complete; 33 checks

python -m py_compile scripts/soul-voice-presence-worker.py scripts/soul-voice-presence-app.py
  passed

voice, transcription, synthesis, and perception regression verifiers
  passed

git diff --check
  passed
```

## Local LLM evaluation

No new LLM eval is required. This slice changes the bounded microphone
lifecycle between ordinary voice-originated Chat turns; it does not change
intent routing, model prompts, or authorization policy.

## Memory and durable state

- No memory keys added.
- Existing Voice Presence transmission continuity is reused.
- No audio is promoted to durable storage.
- Follow-up timeout state exists only in the visible process.

## Lifecycle states

```text
listening
awakened
hearing
thinking
speaking
followup
paused
failed
canceled
complete
```

## Known weaknesses

- This remains half-duplex; speech cannot interrupt Soul's playback.
- Five seconds begins after local playback completion, not after response text
  generation.
- Live comfort and endpoint behavior require Operator microphone testing.

## Human review checklist

- [ ] A spoken reply opens the visibly labeled five-second follow-up window.
- [ ] A follow-up spoken within five seconds reaches the same transmission
      without another “Hey Soul.”
- [ ] Soul's next response opens another fresh follow-up window.
- [ ] Silence returns to wake-word listening without a failure.
- [ ] No microphone process remains active while Soul thinks or speaks.
- [ ] Pause, restart, and window close terminate capture cleanly.
- [ ] A gated follow-up does not inherit authority from the previous turn.
