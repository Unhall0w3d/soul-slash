
# Phase 38 Documentation Registry Refresh

Phase 38 adds a documentation registry refresh assessment and snapshot generator.

## Purpose

The project had drift risk between current-state documentation and the active skill registry.

This phase adds a repeatable way to assess that surface and generate a documentation-only snapshot from:

```text
Soul/skills/registry.yaml
```

## New commands

```bash
ruby bin/soul assess documentation-registry
ruby bin/soul assess documentation-registry --json
ruby bin/soul improve documentation-registry-refresh
```

Aliases:

```bash
ruby bin/soul assess doc-registry
ruby bin/soul assess docs-registry
ruby bin/soul improve doc-registry-refresh
ruby bin/soul improve docs-registry-refresh
```

## Output

```text
docs/SKILL_REGISTRY_SNAPSHOT.md
```

## Scope

Phase 38 does not:

```text
modify the skill registry
change skill behavior
change workflow behavior
invoke Codex
change runtime settings
read secrets
use the network
```

## Result

Soul now has a repeatable documentation drift check and a generated skill registry snapshot.
