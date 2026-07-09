
# Soul Repository Map

This document summarizes the intended shape of the Soul repository.

## Source

```text
bin/
lib/soul_core/
```

Runtime source code lives here.

## Durable verification

```text
scripts/verify-*.rb
```

Durable verifiers validate committed behavior. These should generally be tracked.

Temporary patch or repair scripts should not be tracked:

```text
scripts/patch-*.rb
scripts/repair-*.rb
```

## Product and engineering docs

```text
docs/
docs/assessments/
docs/workflows/
docs/skills/
docs/soul/
```

These describe current behavior, architecture, safety rules, and implemented phases.

## Curated overlay docs

```text
docs/overlays/
```

Only curated overlay process docs belong here. Generated overlay application notes are ignored by default.

## Local/generated areas

```text
Soul/improvement/proposals/
Soul/runtime/
Soul/artifacts/cloud_assist/
Soul/proposals/skills/
overlay_files/
```

These are local/generated/review-only unless explicitly promoted through a future workflow.

## Rule

When in doubt, leave generated artifacts untracked and document the promotion path separately.
