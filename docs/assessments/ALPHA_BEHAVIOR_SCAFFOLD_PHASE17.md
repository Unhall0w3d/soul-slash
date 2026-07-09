# Alpha Behavior Scaffold Phase 17

Phase 17 makes alpha artifacts more useful by generating capability-specific behavior scaffolds.

## New artifact

Alpha generation now writes:

```text
alpha/behavior_scaffold.json
```

The behavior scaffold contains:

```text
planned_artifacts
behavior_steps
risks
```

## Initial capability-specific scaffolds

```text
alpha_skill_generation
model_suitability_routing
vision_screen_understanding
speech_to_text
```

## Behavior

The generated alpha `skill.rb` now exposes:

```ruby
planned_artifacts
behavior_steps
risks
run
```

The `run` method still returns alpha-scaffold output only. It does not perform implementation work.

## Boundaries

This phase remains proposal-local.

Soul must not:

```text
register alpha skills
copy alpha files into production paths
modify workflow registries
install packages
download models
promote automatically
```

## Purpose

This phase moves alpha artifacts from empty placeholders toward reviewable, capability-specific scaffolds without touching production behavior.
