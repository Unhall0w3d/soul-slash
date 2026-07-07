# Skill Template

Use this directory as a starting structure for a Soul skill candidate.

Suggested skill-local files:

```text
README.md
REVIEW.md
evals/
fixtures/
```

The actual implementation location should follow the existing Soul repository structure. This template is documentation-oriented and intentionally does not prescribe language-specific code layout.

## Skill overview

Skill name:

Risk class:

Purpose:

## Brief

Link to the human-authored skill brief:

```text
<path/to/brief.md>
```

## Lifecycle

Expected lifecycle states touched:

- invoked
- context_check
- awaiting_input, if required
- planned, if required
- executing
- complete / failed / canceled / blocked_for_human_review
- reflection_written, if applicable
- exit

## Persistence boundary

This skill must not create services, daemons, watchers, scheduled tasks, cron jobs, systemd units, launch agents, Windows services, long-running loops, or background polling unless the skill brief explicitly approves it.
