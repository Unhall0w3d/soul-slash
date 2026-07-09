
# Feature Direction

This document records the current post-curation feature direction for Soul.

## Current recommendation

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

## Current ranked candidates

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
