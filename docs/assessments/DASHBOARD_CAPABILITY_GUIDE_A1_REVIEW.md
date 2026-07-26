# Dashboard Capability Guide A1 Review

Status: candidate-complete; awaiting live Operator review

## Implemented

- Added a deterministic, registry-backed Dashboard capability guide.
- Added explicit routing for Dashboard/Studio discoverability questions.
- Added surface-specific input and authority guidance for creative work,
  Project Timeline, Core control, and administrative review surfaces.
- Kept Dashboard development statements and Studio opinions in ordinary
  model-backed conversation.
- Registered `dashboard.capabilities.inspect` as a read-only production
  capability.

## Files changed

- `lib/soul_core/dashboard_capability_guide.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `lib/soul_core/chat_responder.rb`
- `Soul/skills/registry.yaml`
- `scripts/verify-dashboard-capability-guide-a1.rb`
- `docs/soul/DASHBOARD_CAPABILITY_GUIDE_A1_BRIEF.md`
- `docs/assessments/DASHBOARD_CAPABILITY_GUIDE_A1_REVIEW.md`
- `docs/CONVERSATIONAL_ORCHESTRATOR.md`
- `docs/ASSISTANT_SKILL_CATALOG.md`

## Commands and deterministic results

```text
ruby scripts/verify-dashboard-capability-guide-a1.rb
  PASS (8 checks)
ruby scripts/verify-chat-intent-and-interaction-boundary.rb
  PASS (35 checks)
ruby scripts/verify-conversational-creative-workflow.rb
  PASS (60 checks)
ruby scripts/verify-core-orchestration.rb
  PASS (20 checks)
ruby bin/soul improve assistant-skill-catalog-refresh
  PASS; 29 registered skills projected
ruby -c changed Ruby files
  PASS
git diff --check
  PASS
```

## Local LLM evaluation

Not required for guide content or safety. Routing safety is deterministic.
Live conversational review remains useful for the surrounding transition back
to ordinary conversation.

## Known weaknesses

- This is a curated capability map, not an automatic promise that every new
  Dashboard operation is Chat-capable.
- Native visual motion, full-duration rendering, publication packaging, Skill
  Studio lifecycle gates, Self Augmentation, and Review Center actions remain
  Dashboard-only where exact conversational mappings do not yet exist.
- Live Gemma and Qwen phrasing around a guide response still requires human
  review; neither model decides the route.

## Memory, lifecycle, and risk

- Durable memory keys added: none.
- Skill-private memory added: none.
- Persistent processes added: none.
- Lifecycle state: `complete`.
- Mutation: none.
- Risk: read-only capability discovery.

## Human review checklist

- [ ] Ask what Soul can do through the Dashboard.
- [ ] Ask what Soul can do in Music Studio and Visual Studio.
- [ ] Confirm ordinary Dashboard-development remarks remain conversational.
- [ ] Confirm partial and Dashboard-only boundaries are understandable.
- [ ] Confirm no capability runs as a side effect of reading the guide.
