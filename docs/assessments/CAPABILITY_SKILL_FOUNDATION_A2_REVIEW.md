# Capability and Skill Foundation A2 Review

## Implementation summary

Candidate-complete for Operator review.

This slice adds a modern packaged `skill_studio.inspect` skill and a bounded
deterministic Chat control used by Voice Presence through the shared runtime.
It projects current proposal, Beta, stage, test, and production registry state.
Every Skill Studio mutation remains behind the existing Dashboard gates. The
slice also reconciles A1 status/count drift and records a five-candidate
fundamental-skill cohort without implementing or importing those candidates.

## Files changed

- `lib/soul_core/skill_studio_chat_controls.rb`
- `lib/soul_core/chat_responder.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `Soul/skills/registry.yaml`
- `Soul/skills/studio/inspect-skill-studio/SKILL.md`
- `Soul/skills/studio/inspect-skill-studio/agents/openai.yaml`
- `Soul/skills/studio/inspect-skill-studio/references/authority.md`
- `Soul/skills/studio/inspect-skill-studio/REVIEW.md`
- `config/operator_capability_catalog.yaml`
- `config/invocation_catalog.yaml`
- `config/project_tracker_seed.json`
- `scripts/verify-skill-studio-conversation-a2.rb`
- `scripts/verify-dashboard-capability-guide-a1.rb`
- `docs/soul/CAPABILITY_SKILL_FOUNDATION_A2_BRIEF.md`
- `docs/guides/SKILL_STUDIO.md`
- `docs/guides/INVOCATION_GUIDE.md`
- `docs/SKILLS.md`
- `docs/CURRENT_STATE.md`
- `Makefile`

## Commands and deterministic results

```text
ruby scripts/verify-skill-studio-conversation-a2.rb
ruby scripts/verify-operator-capability-catalog-a1.rb
ruby scripts/verify-dashboard-capability-guide-a1.rb
ruby scripts/verify-invocation-catalog-a1.rb
ruby scripts/verify-phase12d-skill-studio.rb
ruby scripts/verify-conversation-maintenance-workflow-a1.rb
ruby scripts/verify-conversational-creative-workflow.rb
ruby scripts/verify-project-timeline-a1.rb
ruby scripts/verify-core-orchestration.rb
ruby scripts/verify-voice-presence-a3.rb
python /home/bhones/.codex/skills/.system/skill-creator/scripts/quick_validate.py Soul/skills/studio/inspect-skill-studio
find lib scripts bin Soul/skills -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
git diff --check
```

All listed candidate and regression commands passed.

`ruby scripts/verify-phase12d2-capability-gap-intake.rb` was also run. Its
behavioral intake checks passed, but its existing global source assertion
`intake path adds no background continuation` failed because it rejects any
`setTimeout`/event mechanism found anywhere in the already-modified Dashboard
JavaScript. A2 changes neither `conversation_runtime.rb` nor
`assets/dashboard/dashboard.js`; this is retained as an unrelated brittle test
that requires a separately scoped repair.

## Local LLM eval

Not used. Routing, lookup, projection, and authority behavior are deterministic.
Live Daily, fallback, and spoken phrasing remain an Operator acceptance step.

## Known weaknesses

- Upstream skill candidates do not yet have a separate normalized inventory.
- Proposal title lookup is exact rather than fuzzy.
- Fundamental Skill Cohort A1 is planned, not implemented.
- Live Voice Presence maintenance and Skill Studio inspection remain deferred
  until the Operator is available for a suitable test.

## Memory keys

None.

## Lifecycle states touched

`complete`, `failed`, `awaiting_input`, `canceled`, and
`blocked_for_human_review`.

## Risk classification

Read-only local application and registry inspection. No Studio mutation path is
added.

## Human review checklist

- [ ] Ordinary skill discussion remains conversation.
- [ ] Skill Studio overview reflects current proposals, Betas, and production.
- [ ] Exact proposal and Beta inspection is useful and does not expose authority.
- [ ] Approval, build, trial, promotion, closeout, and deletion stay protected.
- [ ] Voice Presence wording is discoverable and accurate.
- [ ] Fundamental cohort order and boundaries are acceptable.
- [ ] No imported skill, persistence, or second execution path was introduced.
- [ ] Candidate is approved for merge.
