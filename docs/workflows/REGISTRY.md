# Workflow Registry

## Purpose

The workflow registry provides a read-only inventory of supported Soul/ workflows.

It is a first step toward explicit workflow registration and away from ad hoc workflow monkey-patching.

## Commands

Human-readable registry view:

```bash
ruby bin/soul workflows
```

JSON registry view:

```bash
ruby bin/soul workflows --json
```

## Registered workflows

Initial registry entries:

```text
downloads.cleanup
downloads.restore_last_cleanup
weather.report
youtube.play
```

Each entry records:

```text
intent
description
runner
session_statuses
requires_confirmation
write_capable
skills
examples
```

## Boundary

This phase is intentionally read-only metadata.

It does not change how workflows execute yet. Execution still flows through:

```bash
ruby bin/soul do "..."
ruby bin/soul respond "..."
```

Session inspection still flows through:

```bash
ruby bin/soul workflow status latest
ruby bin/soul workflow list
ruby bin/soul workflow clear-complete
```

## Next phase

A later overlay should use this registry to route workflow execution directly, so workflows can be added by registration rather than by patching `WorkflowRunner`, `IntentRouter`, `WorkflowSession`, and `ResponseRenderer`.

## Verification

```bash
ruby scripts/verify-workflow-registry.rb
```
