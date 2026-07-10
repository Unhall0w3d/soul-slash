
# Phase 43 Assistant Skill Catalog

Phase 43 adds an assistant-facing skill catalog assessment and generator.

## Purpose

Soul can now chat, but the chat layer needs skill descriptions that are understandable to humans and useful for future intent routing.

This phase translates the active registry into:

```text
human-readable names
example utterances
risk classifications
confirmation hints
plain explanations
```

## New commands

```bash
ruby bin/soul assess assistant-skill-catalog
ruby bin/soul assess assistant-skill-catalog --json
ruby bin/soul improve assistant-skill-catalog-refresh
```

## Output

```text
docs/ASSISTANT_SKILL_CATALOG.md
```

## Scope

Phase 43 does not:

```text
execute skills
auto-route chat requests
call an LLM
change registry data
change skill behavior
modify runtime chat data
```

## Result

Soul now has a bridge between the raw skill registry and human chat interaction.
