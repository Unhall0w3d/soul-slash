# Invocation Catalog A1 Human Review

status: candidate_complete
risk: Class 1 - read-only local discoverability

## What was implemented

- Curated public invocation definitions for current everyday, knowledge,
  perception, creative, runtime, project, and administration workflows.
- Registry-backed availability validation.
- Bounded read-only `invocations.list` application operation.
- Chat-side Invocation Guide with category and text filters.
- Deterministic Chat responses for the complete catalog, one category, or one
  named invocation.
- Explicit Core, approval, output, and authority-boundary explanations.

## Files changed

- `config/invocation_catalog.yaml`
- `lib/soul_core/invocation_catalog_service.rb`
- application, routing, Dashboard, registry, documentation, and verifier files
  associated with this slice

## Deterministic verification

- `ruby scripts/verify-invocation-catalog-a1.rb` — PASS, 15 checks.
- `ruby scripts/verify-conversational-creative-workflow.rb` — PASS, 60 checks.
- `ruby scripts/verify-core-orchestration.rb` — PASS.
- `ruby scripts/verify-dashboard-capability-guide-a1.rb` — PASS, 8 checks.
- `ruby scripts/verify-assistant-skill-catalog-phase43.rb` — PASS.
- `ruby scripts/verify-project-timeline-a1.rb` — PASS.
- `ruby scripts/verify-phase12b-in-process-application-api.rb` — PASS.
- Notification Cue and Voice Presence A3 regression suites — PASS.
- Ruby and JavaScript syntax checks — PASS.
- `git diff --cached --check` — PASS.

## Local LLM evaluation

Not used. Catalog resolution, filtering, availability, and rendering are
deterministic. Live model, voice, microphone, and screen acceptance is
deliberately deferred.

## Known weaknesses

- The catalog is curated and must be revised when a human-facing workflow
  materially changes.
- Live responsive-layout review is deferred until the Operator returns.
- Catalog coverage does not imply that every Dashboard administration gate
  should become conversational.

## Memory and lifecycle

- Memory keys: none.
- Durable state: none.
- Lifecycle states: `complete` or `failed`.
- Mutation: `none`.

## Human review checklist

- [ ] Open the Invocation Guide from the Chat context rail.
- [ ] Confirm category and text filters are comfortable on the primary display.
- [ ] Inspect music, visual, Core, weather, and screen entries.
- [ ] Ask Chat to show the invocation catalog.
- [ ] Ask how to invoke music production.
- [ ] Confirm none of those inspection actions run a skill or change a Core.
- [ ] Confirm the terminology remains understandable through Voice Presence.
