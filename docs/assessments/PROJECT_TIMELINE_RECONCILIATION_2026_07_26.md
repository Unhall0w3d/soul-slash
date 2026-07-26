# Project Timeline Reconciliation — 2026-07-26

Status: candidate-complete; human review pending

## Outcome

The public Project Timeline seed and the Operator's ignored owner-local ledger
were reconciled with the work currently merged on `main`.

## Timeline changes

- Moved the Project Timeline implementation itself to the completed inventory.
- Updated Chat routing, Voice conversation, Voice live validation, and screen
  perception entries so they describe merged behavior rather than candidate
  pull requests.
- Kept live model, microphone, phone, and multi-monitor acceptance work in
  `needs_review`; deterministic verification was not treated as human
  acceptance.
- Added completed inventory entries for:
  - reversible Active and Released creative-project folders (PR #22);
  - the mobile Chat/Core Presence layout correction (PR #21);
  - accepted-stream completion after a client body disconnect (PR #24).
- Expanded the Dashboard/Core, creative-studio, and Voice/Perception foundation
  records with those current capabilities.
- Preserved all existing private roadmap items, creative projects, local
  proposals, memory, and assessment state.

The owner-local ledger advanced from revision 46 with 28 items to revision 57
with 31 items. It remains ignored by Git at
`Soul/private/project_tracker/state.json`.

## Files changed

- `config/project_tracker_seed.json`
- `docs/assessments/PROJECT_TIMELINE_RECONCILIATION_2026_07_26.md`

## Deterministic verification

- JSON parse of public seed and private ledger — PASS
- `ruby scripts/verify-project-timeline-a1.rb` — PASS
- `ruby scripts/verify-project-release-folders.rb` — PASS
- `ruby scripts/verify-mobile-chat-presence-layout.rb` — PASS
- `ruby scripts/verify-responsive-chat-and-web-research.rb` — PASS
- `ruby scripts/verify-weather-speech-presentation-a1.rb` — PASS
- `ruby scripts/verify-perception-a3.rb` — PASS
- `git diff --check` — PASS

## Local LLM evaluation

None. Timeline reconciliation, state transitions, and regression checks are
deterministic.

## Known review work

- Voice Presence wake reliability and five-second follow-up comfort.
- Weather speech pacing, Fahrenheit pronunciation, and affirmative forecast
  follow-up.
- Fresh focused-window, explicit-monitor, and Dashboard self-recognition
  behavior.
- Invocation Guide and Core-aware workflow acceptance through live Daily and
  fallback models.
- Physical-phone confirmation of the mobile Chat rail.

## Risk

Low. The tracked change updates a public neutral seed and documentation. The
live mutation uses the existing revision-checked ProjectTrackerService against
the ignored owner-local ledger. No project artifacts, memory, proposals,
services, model state, or publication state were changed.

## Human review checklist

- [ ] Refresh Project Timeline and confirm the Now column reflects the remaining
  live-review gates.
- [ ] Open Implemented Inventory and inspect the three new completed entries.
- [ ] Confirm the existing private Later and Backlog items remain present.
- [ ] Confirm no local creative project or Self Improvement record changed.
