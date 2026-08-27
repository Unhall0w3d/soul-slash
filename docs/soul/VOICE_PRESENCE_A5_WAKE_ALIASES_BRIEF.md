# Voice Presence A5 Wake Aliases Brief

Status: human-authorized implementation candidate

## Intent

Improve local wake reliability without turning ordinary speech into a command
stream. Retain `Hey Soul` as the primary phrase, add exact local `Hey Slash`,
and tune recognition against the Operator's live acceptance evidence.

The first installed candidate produced no `Hey Soul` triggers and approximately
70% `Hey Slash` triggers. The revised candidate uses 4.0 / 0.12 for both public
phrases plus bounded unstressed-vowel variants. A conservative reduced-final-L
`Hey Soul` variant uses 3.0 / 0.18 to accommodate the Operator's observed coda
without making that shortened sequence the primary detector.

## Authority and boundaries

- The visible Voice Presence window remains the sole microphone owner.
- Both public phrases and their pronunciation variants authorize one ordinary
  conversational turn only.
- Detection remains CPU-only, local sherpa-onnx keyword spotting.
- Variants are fixed reviewed phoneme sequences for the Operator, not speaker
  identification, training, or general fuzzy phrase matching.
- No cloud wake provider, full-time transcription, background service, login
  persistence, model training, or broad fuzzy phrase matching is added.
- Existing capture, follow-up, Core, skill, confirmation, and destructive-action
  boundaries do not change.
- The installed keyword file changes only through the existing digest-bound
  `voice-presence-install` review flow.

## Acceptance

- Deterministic checks prove all exact token sequences and bounded scores.
- Every visible listening instruction names both accepted phrases.
- Runtime planning exposes both phrases and preserves the existing exact
  confirmation gate.
- Live review exercises several natural `Hey Soul` and `Hey Slash` attempts and
  records false wakes separately from missed wakes.
