
# Doctor Surface

The doctor surface assessment expands health checks beyond the classic `doctor` command without changing doctor behavior.

## Command

```bash
ruby bin/soul assess doctor-surface
ruby bin/soul assess doctor-surface --json
```

Aliases:

```bash
ruby bin/soul assess doctor-coverage
ruby bin/soul assess surface-doctor
```

## Purpose

The classic doctor surface has historically been narrow. It can be green while other user-facing CLI routes still fail.

The doctor surface assessment checks a broader CLI surface:

```text
skills JSON
classic doctor JSON
repo curation JSON
capabilities JSON
Ruby runtime compatibility JSON
Codex loop assessment
skill loop assessment
```

## Legacy surface reporting

The assessment reports legacy workflow files separately from newer handler and assessment routes.

This prevents a green doctor result from being mistaken for full workflow coverage.

## Boundaries

The assessment is read-only.

It does not:

```text
change workflow behavior
change skill behavior
invoke Codex
modify files
read secrets
use the network
```
