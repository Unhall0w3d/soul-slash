
# Documentation Registry Reconciliation

The documentation registry assessment independently checks two current
surfaces against the registered records in `Soul/skills/registry.yaml`:

- human-maintained documentation coverage;
- deterministic generated-snapshot synchronization.

The generated snapshot never counts as evidence that a registry identifier is
covered by its human source documentation.

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

The snapshot is a byte-deterministic projection. It contains no generated
timestamp, and the refresh command does not rewrite an already-current file.
The assessment exposes `snapshot_present` and `snapshot_current` separately.

## Coverage and metadata semantics

Human coverage uses the known registry identifiers and literal skill-ID
boundaries. It does not treat every inline-code token as a possible skill ID.
The JSON report exposes the exact projected IDs, documented IDs, and
`missing_from_docs`.

Registry metadata is projected without invented defaults. When a source record
omits fields, the snapshot says `not declared`; an omitted status is rendered
as `registered (availability not declared)`. Registration alone is not an
availability claim.

`status: ready` and `current: true` require both complete human-documentation
coverage and an exactly synchronized snapshot. Missing human coverage or a
missing/stale snapshot remains visible as a warning and yields
`status: needs_refresh`. Parse/input failures remain blockers.

## Boundaries

The assessment is read-only.

The improve command only writes the generated snapshot document.
It does not rewrite the snapshot when its bytes already match the registry.

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
