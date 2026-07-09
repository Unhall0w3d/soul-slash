
# Documentation Registry Refresh

The documentation registry refresh assessment compares documentation against the active skill registry and can generate a registry snapshot.

## Commands

Assess documentation/registry drift:

```bash
ruby bin/soul assess documentation-registry
ruby bin/soul assess documentation-registry --json
```

Generate the snapshot:

```bash
ruby bin/soul improve documentation-registry-refresh
```

Aliases:

```bash
ruby bin/soul assess doc-registry
ruby bin/soul assess docs-registry
ruby bin/soul improve doc-registry-refresh
ruby bin/soul improve docs-registry-refresh
```

## Source registry

```text
Soul/skills/registry.yaml
```

## Generated snapshot

```text
docs/SKILL_REGISTRY_SNAPSHOT.md
```

## Purpose

This keeps current-state documentation aligned with the active registry without changing skill behavior.

## Boundaries

The assessment is read-only.

The improve command only writes the generated snapshot document.

It does not:

```text
modify the skill registry
activate skills
disable skills
change runtime configuration
invoke Codex
use the network
read secrets
```
