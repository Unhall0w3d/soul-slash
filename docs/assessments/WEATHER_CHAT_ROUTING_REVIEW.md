# Weather Chat Routing Review

## What was implemented

- Registered the existing `weather.report` skill in the modern conversation
  tool catalog and enabled its read-only execution adapter.
- Routed natural typed and spoken weather questions to that skill instead of
  direct model generation.
- Used the configured Home location without an approval gate, while preserving
  explicit per-request location overrides.
- Added current wind direction to the Open-Meteo request and compact response.
- Added an evidence-bound affirmative follow-up so “yes” after the brief report
  retrieves the offered 3-day outlook for the same location.
- Kept casual weather mentions conversational.

## Files changed

- `Soul/skills/weather/report.rb`
- `lib/soul_core/conversation_weather_service.rb`
- `lib/soul_core/conversation_tool_catalog.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `lib/soul_core/conversation_runtime.rb`
- `lib/soul_core/execution_adapter_registry.rb`
- `lib/soul_core/execution_adapter_registry_assessor.rb`
- `scripts/verify-conversation-weather-routing.rb`
- `docs/skills/WEATHER_REPORT.md`
- `docs/assessments/VOICE_PRESENCE_A2_REVIEW.md`

## Commands run

```text
ruby scripts/verify-conversation-weather-routing.rb
ruby scripts/verify-chat-intent-and-interaction-boundary.rb
ruby scripts/verify-conversational-creative-workflow.rb
ruby scripts/verify-voice-presence-a2.rb
git diff --check
systemctl --user restart soul-dashboard.service
```

Two live requests were also sent through the existing Voice Presence
transmission: the brief request and its plain “yes” follow-up.

## Deterministic results

- Weather routing verifier: 9/9 passed.
- Chat intent and interaction boundary verifier: 35/35 passed.
- Conversational creative workflow verifier: 60/60 passed.
- Voice Presence verifier: 32/32 passed.
- Diff whitespace check: passed.
- Live brief request: `complete`, with condition, temperature, wind, and the
  3-day offer.
- Live affirmative follow-up: `complete`, with dated forecast detail.

The older Phase 57 cleanup verifier still reports its pre-existing repository
curation expectation because this working tree intentionally contains several
untracked review candidates. Its weather-adapter-related checks pass; this
candidate does not alter its cleanup safety boundary.

## Local LLM eval

Not used. Weather capability selection and execution are deterministic. The
local model is deliberately excluded from deciding whether this registered
skill exists.

## Known weaknesses

- A Home request requires `SOUL_WEATHER_LOCATION`; otherwise the skill returns
  `awaiting_input` and asks for a location.
- Provider availability and geocoding coverage remain external dependencies.
- Wind direction is omitted when Open-Meteo does not return a direction.
- The short affirmative continuation is bound to recent successful weather
  evidence; an explicit “show the 3-day outlook” remains the clearest command
  after unrelated intervening conversation.

## Memory

No durable memory keys were added or changed. Location comes from the existing
environment configuration or the current request. Weather evidence uses the
shared conversation evidence store.

## Lifecycle states

- `complete`
- `awaiting_input`
- `failed`

No process remains running after the bounded weather invocation returns.

## Risk classification

`read_only`, network-only. The skill writes no user files and requires no
destructive or privileged approval.

## Human review checklist

- [ ] Ask “How is the weather today?” in typed chat.
- [ ] Ask the same question through Voice Presence.
- [ ] Confirm the short response includes condition, temperature, and wind.
- [ ] Answer “yes” and confirm a 3-day outlook appears.
- [ ] Ask for weather in an explicit alternate city.
- [ ] Mention weather conversationally and confirm no fetch occurs.
