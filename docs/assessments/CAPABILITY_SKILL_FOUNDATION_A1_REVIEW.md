# Capability and Skill Foundation A1 Review

## Implementation summary

Candidate-complete for Operator review.

This slice adds a normalized Operator capability catalog, makes Dashboard
self-recognition consume that catalog, registers a bounded
`maintenance.device` skill, and routes explicit Chat or Voice Presence
maintenance requests through the existing fixed device-control service.
Routine non-workstation package maintenance uses a ten-minute digest-bound
conversational confirmation. A later reviewed policy refinement applies the
same bounded confirmation to a separately requested non-workstation reboot;
workstation maintenance and reboot still return a protected handoff.

## Files changed

- `config/operator_capability_catalog.yaml`
- `config/invocation_catalog.yaml`
- `Soul/skills/registry.yaml`
- `Soul/skills/maintenance/maintain-device/SKILL.md`
- `Soul/skills/maintenance/maintain-device/agents/openai.yaml`
- `Soul/skills/maintenance/maintain-device/references/authority.md`
- `lib/soul_core/operator_capability_catalog.rb`
- `lib/soul_core/dashboard_capability_guide.rb`
- `lib/soul_core/conversation_capability_action_store.rb`
- `lib/soul_core/conversation_maintenance_workflow_service.rb`
- `lib/soul_core/conversation_runtime.rb`
- `lib/soul_core/application_facade.rb`
- `scripts/verify-operator-capability-catalog-a1.rb`
- `scripts/verify-conversation-maintenance-workflow-a1.rb`
- `scripts/verify-dashboard-capability-guide-a1.rb`
- `docs/soul/CAPABILITY_SKILL_FOUNDATION_A1_BRIEF.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `config/project_tracker_seed.json`
- `Makefile`

## Commands run and deterministic results

```text
ruby -c lib/soul_core/operator_capability_catalog.rb
ruby -c lib/soul_core/dashboard_capability_guide.rb
ruby scripts/verify-operator-capability-catalog-a1.rb
ruby scripts/verify-dashboard-capability-guide-a1.rb
ruby scripts/verify-invocation-catalog-a1.rb
ruby scripts/verify-conversation-maintenance-workflow-a1.rb
ruby scripts/verify-maintenance-device-control-c1.rb
ruby scripts/verify-maintenance-fleet-status-b1.rb
ruby scripts/verify-conversational-creative-workflow.rb
ruby scripts/verify-voice-presence-a3.rb
ruby scripts/verify-project-timeline-a1.rb
ruby scripts/verify-conversation-weather-routing.rb
ruby scripts/verify-conversational-orchestrator-phase4.rb
python /home/bhones/.codex/skills/.system/skill-creator/scripts/quick_validate.py Soul/skills/maintenance/maintain-device
find lib scripts bin Soul/skills -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
git diff --check
```

All listed commands passed. `ruby scripts/verify-core-orchestration.rb` was
also run and retained its current-main failure for the pre-existing
`Core interface remains event-driven without polling` source assertion. The
same command fails identically in the main worktree; this slice does not edit
the Dashboard Core event code.

## Local LLM eval

Not used for safety or authority validation. Routing and confirmation behavior
are deterministic. Live Daily and fallback Core phrasing tests remain an
Operator review step after merge candidate inspection.

## Known weaknesses

- A1 maps all major surfaces but implements only the first new administrative
  conversational skill.
- Dashboard-only or partially mapped surfaces remain explicitly labeled in
  the catalog and require later vertical slices.
- Live remote maintenance must be tested only when the Operator selects a
  suitable device and approves the candidate.
- Voice Presence shares the Chat runtime, but natural spoken target variation
  needs live acceptance.

## Memory keys

None. Pending confirmation is request-state under
`Soul/runtime/capability_actions`, not durable user memory, and becomes
inactive at a terminal lifecycle state.

## Lifecycle states touched

`complete`, `failed`, `awaiting_input`, `canceled`, and
`blocked_for_human_review`.

## Risk classification

Routine local/remote package mutation and separate non-workstation reboot
using an existing fixed controller. Workstation and other protected actions
remain outside conversational execution.

## Human review checklist

- [ ] Explicit maintenance wording selects the exact intended device.
- [ ] Ordinary maintenance conversation and status questions do not invoke it.
- [ ] The confirmation repeats device, address, adapter, and no-reboot scope.
- [ ] Yes runs only the retained digest-bound plan; no and expiry run nothing.
- [ ] Completion reports progress, receipt, refreshed status, remaining
      updates, reboot state, and issues.
- [ ] Non-workstation reboot requires its own digest-bound preview and never
      chains from maintenance.
- [ ] Atelier maintenance and reboot require an Operator-controlled interface.
- [ ] Capability Guide accurately reports mapped, partial, and unmapped
      surfaces.
- [ ] No persistence, background continuation, safety weakening, or new
      private memory layer was introduced.

## Human review outcome

```text
Outcome: approved for merge
Reviewer: human owner
Date: 2026-07-31
Decision summary: Foundation, authority separation, and first maintenance skill accepted.
Live acceptance: text and Voice Presence maintenance remain deferred until the Operator selects a suitable device.
Required changes: none
```
