# Weather Speech and Fresh Screen A1 Review

## Candidate outcome

This candidate makes compact weather evidence more natural to hear and closes
the observed stale-screen route without broadening ordinary skill invocation.
It is ready for human review, not automatically approved for merge.

## What was implemented

- Added deterministic speech presentation contexts.
- Weather speech expands temperature, percentage, wind, direction, and AQI
  abbreviations; separates compact facts into sentences; and uses a 0.90
  responsive speed factor.
- Dashboard Speak, push-to-talk voice round trips, and Voice Presence derive
  weather context from recorded `weather.report` tool metadata.
- Weather follow-up detection tolerates a harmless leading STT bullet while
  still requiring recent successful weather evidence.
- `What am I looking at?` routes to one fresh active-window capture.
- Voice screen analysis explicitly rejects prior/archive descriptions.
- A deterministic fresh-screen claim guard removes lines containing quoted or
  emphasized literal UI/title names not found in fresh OCR/compositor evidence.

## Files changed

- `lib/soul_core/speech_presentation_service.rb`
- `lib/soul_core/voice_synthesis_service.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `lib/soul_core/voice_screen_understanding_service.rb`
- `lib/soul_core/screen_observation_claim_guard.rb`
- `lib/soul_core/picture_understanding_service.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `assets/dashboard/dashboard.js`
- `scripts/soul-voice-presence-bridge`
- deterministic verification scripts and public documentation named by this
  review.

## Deterministic verification

Required commands:

```bash
ruby scripts/verify-weather-speech-presentation-a1.rb
ruby scripts/verify-conversation-weather-routing.rb
ruby scripts/verify-perception-a1.rb
ruby scripts/verify-perception-a3.rb
ruby scripts/verify-voice-synthesis-a0.rb
```

Results: all checks passed. `scripts/soul-runtime-test.sh --fast` also passed
against the configured local provider. The isolated worktree does not contain
the ignored `.env`, so `make test-fast` itself stopped at configuration before
the equivalent runtime script was run with the local configuration.

## Local LLM evaluation

No local LLM evaluation is used as a safety or routing authority. Live Gemma
validation remains an Operator review item because this branch is isolated from
the currently running dashboard.

## Known weaknesses

- The claim guard validates explicit quoted/emphasized names and proper-name
  phrases; it is not a complete factual verifier for every visual description.
- Fresh OCR may miss small text. The safe result is omission, not invention.
- Weather prosody still depends on the selected local voice.
- Live listening and fresh-window testing must be repeated after deployment.

## Memory, lifecycle, and risk

- Memory keys added or used: none.
- Lifecycle states touched: existing `complete`, `awaiting_input`, `failed`, and
  `blocked_for_human_review` paths only.
- Screen capture remains ephemeral and bounded to one request.
- Risk classification: read-only local perception and request-private local
  speech; no new mutation, persistence, privilege, listener, or approval path.

## Human review checklist

- [ ] Hear a short weather report and confirm pace, pauses, and Fahrenheit.
- [ ] Answer the three-day offer with “Yeah” and confirm real skill evidence.
- [ ] Ask “What am I looking at?” while changing the focused window.
- [ ] Confirm the answer reflects the current active window, not old chat text.
- [ ] Confirm invented titles or control names are omitted rather than asserted.
- [ ] Confirm ordinary conversation mentioning screens does not capture pixels.
