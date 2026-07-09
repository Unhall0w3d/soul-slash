# Capability Matrix Phase 13

Phase 13 adds Soul's capability matrix.

The capability matrix maps current skills, workflows, handlers, contracts, and model runtime status into user-facing capabilities.

Commands:

```bash
ruby bin/soul assess capabilities
ruby bin/soul assess capabilities --json
ruby bin/soul assess capabilities --persist
ruby bin/soul assess capability-matrix --json
```

## What it reports

```text
available capabilities
partial capabilities
missing capabilities
blocked capabilities
current support
missing prerequisites
recommendations
```

## Initial capabilities

```text
youtube_playback
workflow_contract_enforcement
environment_assessment
model_runtime_assessment
local_model_reasoning
skill_brief_pipeline
alpha_skill_generation
model_suitability_routing
vision_screen_understanding
speech_to_text
```

## Persistence

When `--persist` is supplied, Soul writes:

```text
Soul/runtime/capability_matrix.json
```

This is the first durable local runtime map of what Soul can and cannot currently do.

## Boundaries

Soul must not:

```text
modify skills
modify workflows
download models
install packages
promote capabilities automatically
```

Capability recommendations are advisory only.

## Future phases

Future phases should add:

```text
improvement proposal generation from capability gaps
alpha skill generator
model capability registry
vision/screenshot capability proposal
speech-to-text capability proposal
```
