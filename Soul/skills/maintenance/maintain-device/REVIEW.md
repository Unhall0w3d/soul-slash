# Maintain Device Skill Candidate Review

## Skill

Name: `maintenance.device`

Risk class: routine package mutation through an existing fixed controller

Branch/checkpoint: `codex/capability-skill-foundation`

Date: 2026-07-30

## Candidate status

```text
candidate_complete
human_review_required
```

## Implementation summary

The skill resolves one exact managed fleet device, obtains the existing
server-authored maintenance preview, repeats the target and no-reboot scope,
and retains its digest-bound confirmation for at most ten minutes. A short
affirmative response may execute routine package maintenance on a
non-workstation device. Completion reports live progress, receipt, refreshed
fleet status, remaining updates, reboot state, and fixed-step issues.

Reboot and workstation maintenance cannot execute through Chat or Voice
Presence affirmation. They return a protected handoff to an
Operator-controlled Dashboard, terminal, or Noctalia action.

## Files changed

See `docs/assessments/CAPABILITY_SKILL_FOUNDATION_A1_REVIEW.md` for the complete
candidate file inventory.

## Commands and deterministic results

```text
ruby scripts/verify-conversation-maintenance-workflow-a1.rb
ruby scripts/verify-operator-capability-catalog-a1.rb
ruby scripts/verify-dashboard-capability-guide-a1.rb
ruby scripts/verify-invocation-catalog-a1.rb
python /home/bhones/.codex/skills/.system/skill-creator/scripts/quick_validate.py Soul/skills/maintenance/maintain-device
```

All passed before candidate review.

## Local LLM eval

Not used. Invocation, target matching, authority, expiry, and execution are
deterministic. Live phrasing review on Daily and fallback Cores remains
pending.

## Memory keys

None. Short-lived pending action state is not durable user memory.

## Lifecycle states

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

## Persistence and safety

```text
Persistent service added: no
Daemon or watcher added: no
Scheduled task added: no
Background continuation added: no
Automatic retry added: no
Arbitrary command path added: no
Existing confirmation digest bypassed: no
Protected action conversational execution added: no
Skill-private durable memory added: no
```

## Known weaknesses

- Only exact currently managed fleet targets are supported.
- Voice phrasing variability requires live acceptance.
- Maintenance can remain foreground for the fixed controller's bounded
  45-minute timeout.
- Other Dashboard surfaces remain separate later skill slices.

## Human review checklist

```text
[ ] Ordinary conversation does not trigger maintenance
[ ] Exact target, address, adapter, and no-reboot scope are clear
[ ] Yes executes only the retained fresh plan
[ ] No and expired confirmation execute nothing
[ ] Receipt and refreshed fleet evidence are useful
[ ] Reboot and workstation maintenance require an Operator gesture
[ ] Voice and text behavior are acceptably consistent
[ ] Known weaknesses are acceptable
[ ] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: pending
Reviewer: human owner
Date: pending
Decision summary: pending
Required changes: pending
```
