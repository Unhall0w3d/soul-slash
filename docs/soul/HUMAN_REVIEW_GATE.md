# Soul Human Review Gate

Candidate-complete work is not approved work.

Codex may produce candidate-complete skills by implementing, testing, evaluating, and repairing against the written brief. Human review decides whether the work may be merged, released, enabled, or trusted for repeated use.

## Reviewer responsibilities

The human reviewer should verify:

- The skill matches the approved brief
- No out-of-scope behavior was added
- No persistence or background execution was introduced
- Risk class is correct
- Memory keys are appropriate and documented
- Confirmation gates are intact
- Deterministic tests are meaningful and passing
- Local LLM evals are useful and not being used as safety proof
- Failure behavior is predictable
- Logs/reflection are useful
- The user-facing behavior is acceptable

## Persistence review

Explicitly check for:

- Services
- Daemons
- Watchers
- Cron jobs
- systemd units
- launch agents
- Windows services
- Scheduled tasks
- Long-running loops
- Background polling
- Network listeners
- Hidden child processes

If any appear without explicit approval, reject the candidate.

## Safety review

For any skill that changes files, local state, external systems, or durable memory, verify:

- Planning and execution are separated when required
- Confirmation gates are explicit
- Dry-run/preview behavior exists where practical
- Logs record changed paths or external targets
- Rollback/restore visibility exists where practical
- LLM output is not treated as authorization

## Memory review

Verify:

- Durable memory uses shared infrastructure
- New keys are documented
- First-use behavior is clear
- Update/forget behavior exists where appropriate
- Sensitive or personal data is not stored unnecessarily

## Review outcomes

Choose one:

```text
approved_for_merge
requires_changes
rejected_scope_drift
rejected_safety_policy
blocked_needs_design_decision
```

## Required review note

Every candidate should have a short review note:

```text
Review outcome:
Reviewer:
Date:
Decision summary:
Required changes, if any:
```
