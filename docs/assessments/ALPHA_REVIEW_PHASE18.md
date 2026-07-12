
# Alpha Review Phase 18

Phase 18 adds review-only assessment for generated alpha artifacts.

## Commands

```bash
ruby bin/soul improve alpha-review --latest
ruby bin/soul improve alpha-review --latest --json
ruby bin/soul improve alpha-review --proposal-rank 1
ruby bin/soul improve alpha-review --proposal Soul/improvement/proposals/<proposal-folder>
```

Alias:

```bash
ruby bin/soul improve review-alpha --latest
```

## Review checks

The alpha review checks:

```text
required alpha files
manifest safety boundaries
behavior scaffold shape
test case metadata
alpha verifier result
promotion blockers
warnings
```

## Required files

```text
README.md
implementation_plan.md
skill.rb
verify-alpha.rb
test_cases.json
behavior_scaffold.json
promotion_checklist.md
alpha_manifest.json
```

## Readiness statuses

```text
review_ready
review_ready_with_warnings
blocked
```

## Boundaries

This phase is review-only.

Soul must not:

```text
promote alpha artifacts
modify production skill paths
modify registries
install packages
download models
change generated alpha files during review
```

Promotion is explicitly not implemented in this phase.
