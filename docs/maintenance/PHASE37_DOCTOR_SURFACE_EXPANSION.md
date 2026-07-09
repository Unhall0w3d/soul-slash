
# Phase 37 Doctor Surface Expansion

Phase 37 adds a read-only `doctor-surface` assessment.

## Purpose

Codex previously identified that the classic doctor surface was narrow and could appear green even when other user-facing workflows were not covered.

This phase does not replace doctor. It adds a broader assessment route that verifies important CLI surfaces and reports legacy workflow files separately.

## New commands

```bash
ruby bin/soul assess doctor-surface
ruby bin/soul assess doctor-surface --json
```

Aliases:

```bash
ruby bin/soul assess doctor-coverage
ruby bin/soul assess surface-doctor
```

## Checks

```text
skills JSON
doctor JSON
repo curation JSON
capabilities JSON
Ruby runtime compatibility JSON
Codex loop JSON/text
skill loop text
legacy workflow file presence
```

## Scope

Phase 37 does not:

```text
change classic doctor behavior
change workflow behavior
change skill behavior
invoke Codex
modify runtime configuration
read secrets
use the network
```

## Result

Soul now has a broader doctor-adjacent surface check before additional workflow or skill expansion.
