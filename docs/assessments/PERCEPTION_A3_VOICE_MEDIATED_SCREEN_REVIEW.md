# Perception A3 Voice-Mediated Screen Review

```text
status: deterministic candidate complete; dashboard self-recognition live test deferred and untested
date: 2026-07-25
risk: local-private, voice-authorized one-shot capture of potentially sensitive pixels
human_merge_approval: required
```

## Candidate outcome

> **Live validation:** The new dashboard self-recognition map is untested
> against the running interface. Revisit dashboard identification, active-panel
> accuracy, exact control labels, and hidden-versus-visible state when the
> Operator is back at the computer.

The visible Voice Presence application can carry an unmistakable spoken request
for one current monitor, active window, or selected region through the existing
A2 capture and A1 picture-understanding paths.

The deterministic router requires both perception intent and a current-screen
target. It checks Daily Core before capture, never transfers Cores silently,
retains no screenshot pixels, and leaves ordinary screen discussion on the
normal conversation path.

The hardened router also recognizes explicit refresh/update-view wording,
all monitors, left/right or numbered monitors, and currently visible
workspaces. Hidden workspaces return `awaiting_input`; Soul never switches one
silently.

Fresh captures corroborated as Soul's dashboard receive a reviewed map of its
primary surfaces. Soul can therefore identify and explain its own interface,
while current panel, project, control, and approval state must still come from
fresh pixels and exact OCR.

## Files changed

- `lib/soul_core/voice_screen_understanding_service.rb`
- `lib/soul_core/screen_capture_service.rb`
- `lib/soul_core/picture_understanding_service.rb`
- `lib/soul_core/conversation_evidence_followup_router.rb`
- `lib/soul_core/phase7_evidence_followup_router_assessor.rb`
- `scripts/soul-voice-presence-bridge`
- `scripts/soul-voice-presence-app.py`
- `scripts/verify-perception-a3.rb`
- voice guide, README, current state, roadmap, brief, and this review

## Deterministic results

- explicit screen, window, and region routing: PASS
- refresh-view and visible-screen wording always routes through fresh capture:
  PASS
- all, spatial, numbered, and visible-workspace targeting: PASS
- hidden workspace does not cause a compositor switch: PASS
- capability discussion remains conversation: PASS
- ordinary screen mention remains conversation: PASS
- perception verb without a current target remains conversation: PASS
- Core readiness precedes capture: PASS
- capture and analysis execute exactly once: PASS
- exact transcript becomes the picture question: PASS
- pixel retention remains false: PASS
- completed exchange joins Voice Presence continuity: PASS
- non-Daily Core captures nothing: PASS
- Core requirement becomes a spoken-ready exchange: PASS
- canceled region is terminal and never analyzed: PASS
- unmatched voice reaches ordinary `chats.send`: PASS
- terminal explanations with audio are spoken: PASS
- no Core switch or screen control: PASS
- long new requests cannot be hijacked by a generic evidence pronoun: PASS
- vision must verify text in pixels rather than echo identifying hints: PASS
- bounded local OCR preserves exact labels without entering conversation text:
  PASS
- compositor inventory identifies windows and local geometry actually present:
  PASS
- Soul's Voice Presence identity and reviewed control names are supplied only
  when fresh pixels/OCR support them: PASS
- Soul's dashboard identity and reviewed surface purposes are supplied only
  when its title or multiple exact dashboard markers support them: PASS
- reviewed dashboard knowledge cannot be presented as current visible state:
  PASS

## Live host result

With Daily Core active and Voice Presence closed, the production A3 service
received this explicit integration request:

> Look at the active window and briefly identify the application and visible
> page. This is a bounded voice perception integration test.

It checked the Core, captured one active-window screenshot, invoked Gemma once,
identified the visible Opera/YouTube page, appended the observation to the
dedicated Voice Presence transmission, reported `image_retained: false`, and
left both A2 capture staging and A1 picture staging empty.

The later Operator trace exposed three routing failures in the original A3
candidate. Two screen requests entered `direct_model` with no perception
digest, allowing the chat model to repeat an old captured title and then invent
a different title. A third explicit screen request entered
`evidence_followup` and rendered stale weather evidence. No new screenshot was
taken in any of those turns. The deterministic parser and evidence follow-up
boundary now cover those exact phrases. Original command audio was unavailable
by design because Voice Presence deletes request WAVs at terminal return;
retained transcripts and orchestration metadata supplied the diagnostic
evidence.

A later fresh right-monitor capture correctly entered `picture_understanding`
with digest `36e5865482f774b935a55504c0c5597883f8191aa1d460ae27a04a3dc44c48a7`.
Gemma described the large video region accurately but failed to recognize
Soul's own lower window and invented quest-like names for its small controls.
A temporary diagnostic capture confirmed the real labels. Tesseract 5.5 read
`LOCAL VOICE PRESENCE`, `Soul /`, `Pause listening`, `Restart presence`, and
`Close presence` exactly. The production path now supplies this bounded OCR
plus Hyprland window identity/geometry as ephemeral corroboration and forbids
semantic label invention.

## Commands

- `ruby scripts/verify-perception-a3.rb` - PASS
- `ruby scripts/verify-perception-a2.rb` - PASS
- `ruby scripts/verify-perception-a1.rb` - PASS
- Phase 7 evidence follow-up assessor - PASS
- `ruby -c lib/soul_core/voice_screen_understanding_service.rb` - PASS
- `ruby -c scripts/soul-voice-presence-bridge` - PASS
- `python -m py_compile scripts/soul-voice-presence-app.py` - PASS
- production A3 service integration call - PASS

## Memory, lifecycle, and risk

- Shared memory keys: none.
- Soul Vault writes: none.
- Durable pixels: none.
- Durable OCR/compositor context: none.
- Durable text: ordinary Voice Presence user/assistant messages.
- Lifecycle: `complete`, `failed`, `canceled`, `awaiting_input`,
  `blocked_for_human_review`.
- Risk: local-private, voice-authorized one-shot capture of potentially
  sensitive pixels.
- Mutation: one ephemeral screenshot plus the canonical chat exchange.

## Known weaknesses

- Speech-to-text errors can prevent an intended request from matching or alter
  its question. The conservative router prefers no capture over inference.
- Voice mode provides no screenshot preview and never retains pixels. Dashboard
  Screen remains the reviewed surface for preview and retention.
- Region requests require one foreground desktop selection after the utterance.
- A running Voice Presence window must be restarted once to load this project
  revision.

## Human checklist

- [ ] Restart or launch Voice Presence from the current project files.
- [ ] Say `Hey Soul, look at my screen and tell me what application is open`.
- [ ] Confirm the portrait/status identifies capture and inspection.
- [ ] Confirm the spoken answer matches the current monitor.
- [ ] Repeat on AMD-Free Core and confirm no pixels are captured.
- [ ] Mention screen-understanding work conversationally and confirm no capture.
- [ ] Change the focused window, ask Soul to refresh its view, and confirm the
      new response has a new perception digest.
- [ ] Ask for left monitor, right monitor, all monitors, monitor 1/2, and one
      currently visible workspace.
- [ ] Ask for a hidden workspace and confirm Soul requests input rather than
      changing workspaces.
- [ ] Cancel a spoken selected-region request.
- [ ] Close Voice Presence and confirm no capture or microphone child remains.
