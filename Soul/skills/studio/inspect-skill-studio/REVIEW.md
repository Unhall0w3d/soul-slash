# Inspect Skill Studio Candidate Review

## Skill

Name: `skill_studio.inspect`

Risk class: read-only local state projection

Branch/checkpoint: `codex/capability-skill-foundation-a2`

Date: 2026-08-01

## Candidate status

```text
candidate_complete
human_review_required
```

## Implementation summary

The skill exposes current proposal, Beta, stage, test, and production registry
evidence through the shared Chat path used by Voice Presence. It recognizes
only explicit inventory and detail requests. Every Skill Studio mutation stays
behind its existing Dashboard gate and returns a protected handoff.

## Commands and deterministic results

See `docs/assessments/CAPABILITY_SKILL_FOUNDATION_A2_REVIEW.md` for the complete
command and result inventory.

## Local LLM eval

Not used. Request matching, inventory projection, exact-title lookup, and the
mutation boundary are deterministic.

## Memory keys

None.

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
Mutation path added: no
Existing Skill Studio gate weakened: no
Skill-private durable memory added: no
```

## Known weaknesses

- Spoken phrasing outside the bounded request patterns requires later live use
  evidence.
- Upstream skill candidates do not yet have a separate normalized inventory.
- This skill explains protected actions but cannot prepare their previews.

## Human review checklist

```text
[x] Ordinary skill conversation does not trigger Studio inspection
[x] Overview counts reflect current local state
[x] Proposal and Beta detail require exact current identifiers
[x] Production listing invokes no skill
[x] Approval, build, trial, promotion, closeout, and deletion remain protected
[x] Voice phrasing is acceptably discoverable for the reviewed contract
[x] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: approved
Reviewer: human owner
Date: 2026-08-01
Decision summary: Read-only Skill Studio inventory and retained human-gate boundary accepted.
Required changes: none
```
