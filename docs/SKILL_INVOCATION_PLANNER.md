
# Skill Invocation Planner

Phase 46 adds safe execution plans for routed chat intents.

## Purpose

Soul can now route simple chat requests to candidate skills.

The planner turns that route into a safe plan:

```text
candidate skill
risk category
confirmation requirement
blocked execution status
owner-facing explanation
```

## Commands

```bash
ruby bin/soul assess skill-invocation-planner
ruby bin/soul assess skill-invocation-planner --json
```

Aliases:

```bash
ruby bin/soul assess invocation-planner
ruby bin/soul assess skill-planner
```

## Safety posture

Phase 46 does not execute skills.

Every plan must say:

```text
executable_now: false
```

This is intentional.

## Future use

The next layer should add an approval gate and executor that can safely run read-only skills first, then approval-required skills later.
