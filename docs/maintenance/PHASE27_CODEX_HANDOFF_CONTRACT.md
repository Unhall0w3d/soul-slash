
# Phase 27 Codex Handoff Contract

Phase 27 adds a bounded Codex handoff contract.

## Purpose

Codex should not jump into the middle of the repository and improvise.

This phase defines the package structure needed before Codex receives any implementation task.

## New commands

```bash
ruby bin/soul assess codex-handoff
ruby bin/soul assess codex-handoff --json
ruby bin/soul assess codex-handoff --task model_suitability_registry
ruby bin/soul assess codex-handoff --task model_suitability_registry --write --json
```

## Scope

Phase 27 does not:

```text
invoke Codex
send repo context to cloud providers
write implementation output
modify production behavior
enable providers
read secrets
change runtime configuration
```

## Required handoff fields

```text
task
repo_context
allowed_files
forbidden_files
acceptance_criteria
verifier_expectations
security_boundaries
output_format
rollback_notes
```

## Next phase

Phase 28 should add a dry-run review loop that evaluates Codex-produced artifacts against the handoff contract.
