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
[ ] Ordinary skill conversation does not trigger Studio inspection
[ ] Overview counts reflect current local state
[ ] Proposal and Beta detail require exact current identifiers
[ ] Production listing invokes no skill
[ ] Approval, build, trial, promotion, closeout, and deletion remain protected
[ ] Voice phrasing is acceptably discoverable
[ ] Candidate is approved for merge
```
