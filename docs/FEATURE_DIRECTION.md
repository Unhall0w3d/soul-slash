
# Feature Direction

This document records the legacy Phase 24 post-curation ranking returned by `assess feature-direction`.

The top foundational candidates from that ranking—model suitability, Alpha/Beta implementation planning, Codex handoff/review, and the dashboard skill lifecycle—were delivered in later phases. For the current program position, see `docs/CURRENT_STATE.md` and `docs/CONVERSATIONAL_SOUL_ROADMAP.md`.

## Phase 24 recommendation

The recommended next capability is:

```text
model_suitability_registry
```

## Why

A model suitability registry is the safest foundational next step after repository hygiene and alpha pipeline work.

It supports future work without adding risky automation:

```text
speech-to-text assessment
screen understanding assessment
alpha implementation planning
local/cloud model routing policy
```

## Decision policy

Feature direction should prefer:

```text
low-risk foundational work
capability-gap closure
local-first behavior
human approval before implementation
clear runtime boundaries
no background services by default
no implicit cloud routing
```

## Phase 24 ranked candidates

```text
1. model_suitability_registry
2. alpha_implementation_behavior
3. speech_to_text_assessment
4. screen_understanding_assessment
```

## Boundaries

The feature direction assessment is advisory only.

It must not:

```text
download models
install packages
enable providers
record audio
capture screenshots
promote alpha artifacts
change runtime configuration
```

## Commands

```bash
ruby bin/soul assess feature-direction
ruby bin/soul assess feature-direction --json
```
