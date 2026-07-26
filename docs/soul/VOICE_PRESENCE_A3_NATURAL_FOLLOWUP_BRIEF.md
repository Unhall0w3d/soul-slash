# Voice Presence A3 - Natural Follow-Up Window

## Purpose

Allow one natural spoken follow-up after Soul finishes speaking without
requiring the Operator to repeat **Hey Soul** for every turn.

## Lifecycle

```text
Hey Soul
-> one bounded utterance
-> Soul thinks and speaks
-> response playback completes
-> visible five-second follow-up window opens
-> speech begins:
     capture one normal bounded utterance
     -> Soul thinks and speaks
     -> open a fresh five-second follow-up window
-> no speech:
     close follow-up window
     -> return to wake-word listening
```

Each completed response opens one new bounded opportunity. This permits a
natural multi-turn exchange while the Operator remains engaged, but it never
becomes an indefinite open microphone.

## Bounds and privacy

- Follow-up speech must begin within five seconds.
- Once speech begins, the existing 30-second utterance and 1.2-second trailing
  silence limits apply.
- No-speech expiry is normal, not a failure.
- A too-short, closed, or invalid microphone path retains existing safe failure
  handling.
- The follow-up recorder exists only during the visible window.
- Audio remains request-private and is deleted after the turn.
- Closing or pausing Voice Presence terminates the follow-up recorder.
- Three actual failures still pause the application; simple expiry does not
  increment the failure count.

## Authority

A follow-up is an ordinary voice-originated turn. It does not inherit approval
from the previous request and does not bypass any skill, Core, destructive,
privileged, generation, or publication gate.

## Interface

The portrait and status explicitly show:

- `Follow-up open`
- `Listening for a natural reply`
- expiry back to `Listening locally for “Hey Soul”`

No hidden follow-up capture occurs while Soul is thinking or speaking.

## Acceptance

- playback completion sends `followup`, not ordinary wake resume;
- worker opens the recorder only after receiving `followup`;
- speech-start window is exactly bounded by the manifest;
- one follow-up can lead to another after Soul responds;
- silence returns to wake listening without failure;
- normal wake detection remains suspended during follow-up;
- pause, close, restart, failure, audio cleanup, and ordinary intent-routing
  behavior remain intact.
