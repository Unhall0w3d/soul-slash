# Voice Conversation A1 Brief

```text
date: 2026-07-24
human_authorization: approved in the active development conversation
implementation_authorized: yes
human_round_trip_review_required: yes
risk: Class 3 - explicit microphone action submits one transcript and speaks one reply
```

## Objective

Turn the existing Chat push-to-talk interaction into one bounded conversational
round trip. The Operator's explicit microphone action authorizes capture,
transcription, submission through the ordinary chat router, and playback of
the resulting Soul response using the currently selected voice and delivery
profile.

## Authorized vertical slice

- Preserve explicit Start and Stop recording controls and the sixty-second
  capture ceiling.
- After successful transcription, place the text in the composer and submit it
  through the existing `chats.send` streaming path.
- Keep typed-form submission unchanged and silent.
- After the chat request reaches a terminal result, speak only the newest
  assistant response using the existing Responsive/Expressive synthesis path.
- Preserve normal intent routing, skill gates, Core orchestration, failure
  behavior, and conversation persistence.
- A transcription, chat, or synthesis failure terminates visibly; no process
  waits in the background for another turn.

## Restraint

- No wake word, always-listening process, daemon, queue, polling loop, or new
  listener.
- The transcript is sent only because the Operator deliberately opened and
  stopped this push-to-talk interaction.
- No recording or synthesized audio is retained.
- Voice does not bypass any skill preview or confirmation gate.
- One microphone action produces at most one user message and one spoken
  assistant response.

## Required evidence

- deterministic transcription remains bounded and disposable;
- voice-originated submission uses the same chat transport as typed input;
- typed messages do not trigger automatic speech;
- one terminal assistant record is selected for playback;
- errors do not resend, duplicate, or leave the microphone open;
- live authenticated microphone-to-spoken-reply review.
