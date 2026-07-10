
# Assistant Skill Catalog Design

The assistant-facing skill catalog translates the registry into language useful for chat, intent routing, and safe skill invocation planning.

## Commands

```bash
ruby bin/soul assess assistant-skill-catalog
ruby bin/soul assess assistant-skill-catalog --json
ruby bin/soul improve assistant-skill-catalog-refresh
```

Aliases:

```bash
ruby bin/soul assess skill-catalog
ruby bin/soul assess skills-catalog
ruby bin/soul improve skill-catalog-refresh
ruby bin/soul improve skills-catalog-refresh
```

## Generated catalog

```text
docs/ASSISTANT_SKILL_CATALOG.md
```

## Why this exists

The raw skill registry is machine-oriented.

The chat layer needs something more human:

```text
human-readable skill names
plain descriptions
example utterances
risk language
confirmation expectations
routing hints
```

## Risk language

```text
read_only: can inspect or report without changing local state
review_only: drafts or reviews artifacts without promotion
network_or_provider_check: may involve configured provider/API testing
approval_required: must ask before changing local state
unknown: needs routing caution until classified
```

## Boundaries

This phase does not execute skills.

It does not promote skills.

It does not mutate the registry.

The catalog is routing support, not permission to act.
