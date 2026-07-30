
# Phase 38 Documentation Registry Refresh

This historical Phase 38 title and filename are retained as implementation
evidence. The current behavior is a documentation registry reconciliation
assessment plus a deterministic snapshot generator.

## Purpose

The project had drift risk between current-state documentation and the active skill registry.

This phase added a repeatable way to assess that surface and generate a
documentation-only snapshot from:

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

## Current reconciliation semantics

The assessment reports human-documentation coverage independently from
snapshot synchronization. Only human-maintained source documents count toward
coverage; the generated snapshot cannot satisfy that check. Known registry
identifiers are matched literally at skill-ID boundaries, avoiding false IDs
from unrelated inline-code tokens.

The snapshot is a deterministic, exact projection of the registry:

```text
no generated timestamp
no fabricated unknown or uncategorized metadata
not declared for absent descriptive metadata
registered (availability not declared) for absent status
no write when the tracked snapshot is already current
```

The JSON assessment exposes the exact registry projection,
`missing_from_docs`, `human_documentation_complete`, and `snapshot_current`.
Missing human coverage or stale snapshot content prevents a `ready`/`current`
result. Registry/input failures remain blockers.

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

Soul has a repeatable, deterministic documentation drift check that
distinguishes human coverage from generated evidence without changing the
skill registry.
