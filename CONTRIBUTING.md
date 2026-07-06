# Contributing

Soul/ is currently experimental and personal-first.

## Development style

Use small, reviewable overlays or focused commits.

Preferred change shape:

```text
one idea
one overlay or focused commit
clear test commands
no hidden side effects
```

## Safety expectations

Any new skill must declare:

- risk level
- whether it writes files
- whether approval is required
- expected output format
- verification fields

Write-capable skills must provide a dry-run or plan-first mode unless there is a strong reason not to.

## Test expectations

At minimum, run:

```bash
ruby -c bin/soul
find lib Soul/skills -name "*.rb" -print0 | xargs -0 -n1 ruby -c
```

For runtime-backed checks, run the relevant `ruby bin/soul ...` commands documented in the overlay or PR.
