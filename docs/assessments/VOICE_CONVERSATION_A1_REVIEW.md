# Voice Conversation A1 Review

## Candidate summary

One explicit push-to-talk interaction now covers capture, local transcription,
ordinary Chat submission, and playback of the resulting Soul reply. Typed
messages remain silent. Voice-originated text uses the same `chats.send`
stream, intent router, skill gates, Core orchestration, and persistence as a
typed message.

The selected Voice and Delivery profiles are read only when the terminal
assistant response is ready. Responsive uses the CPU voice path; Expressive
uses the already reviewed bounded Chatterbox resource transaction.

## Files changed

- `assets/dashboard/dashboard.js`
- `docs/soul/VOICE_CONVERSATION_A1_BRIEF.md`
- `scripts/verify-voice-transcription-a0.rb`
- `docs/assessments/VOICE_CONVERSATION_A1_REVIEW.md`

## Verification

```text
node --check assets/dashboard/dashboard.js: PASS
ruby scripts/verify-voice-transcription-a0.rb: PASS
ruby scripts/verify-voice-synthesis-a0.rb: PASS
ruby scripts/verify-voice-synthesis-a1-expressive.rb: PASS
```

## Lifecycle, memory, and risk

```text
recording retained: no
synthesized audio retained: no
new memory keys: none
conversation mutation: one ordinary user message and its assistant reply
lifecycle states: complete, failed, awaiting_input, canceled
new service/listener/daemon/queue/polling: none
risk: explicit voice gesture now authorizes one bounded conversational turn
```

## Known weaknesses

- Browser autoplay policy may still reject delayed audible playback on some
  mobile/browser combinations; the response remains in Chat with its explicit
  Speak control if that occurs.
- Push-to-talk submits the complete composer after inserting the transcript.
  Existing typed draft text therefore becomes part of that deliberately
  submitted voice-originated message.
- Expressive delivery includes cold model-load and possible Core restoration
  latency.

## Human review checklist

- [ ] Record and stop one short phrase.
- [ ] Confirm exactly one user message is stored.
- [ ] Confirm Soul produces exactly one reply.
- [ ] Confirm that reply is spoken with the selected identity and delivery.
- [ ] Confirm a typed message does not speak automatically.
- [ ] Confirm transcription/chat/synthesis failures remain terminal and visible.
