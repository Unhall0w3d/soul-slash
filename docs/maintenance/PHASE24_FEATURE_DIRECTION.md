
# Phase 24 Feature Direction

Phase 24 returns the project from repository hygiene work to product direction.

## Purpose

Add a read-only feature direction assessment that ranks next bounded capability candidates.

## New command

```bash
ruby bin/soul assess feature-direction
ruby bin/soul assess feature-direction --json
```

Aliases:

```bash
ruby bin/soul assess features
ruby bin/soul assess next-feature
```

## Candidates

```text
model_suitability_registry
alpha_implementation_behavior
speech_to_text_assessment
screen_understanding_assessment
```

## Recommended next phase

```text
phase_25: model_suitability_registry
```

## Rationale

Model suitability is foundational and low risk. It helps Soul reason about which local or cloud model class is appropriate for a task without enabling automatic routing, installing packages, downloading models, or storing secrets.

## Scope

Phase 24 does not implement the recommended feature.

It only adds the assessment and documentation.
