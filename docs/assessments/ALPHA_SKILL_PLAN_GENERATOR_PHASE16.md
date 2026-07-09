# Alpha Skill Plan Generator Phase 16

Phase 16 improves alpha generation by adding proposal selection helpers and an implementation plan artifact.

## New alpha selection options

```bash
ruby bin/soul improve alpha --latest
ruby bin/soul improve alpha --proposal-rank 1
ruby bin/soul improve alpha --proposal Soul/improvement/proposals/<proposal-folder>
```

## New artifact

Alpha generation now writes:

```text
alpha/implementation_plan.md
```

The implementation plan is generated from proposal metadata and includes:

```text
summary
objective
scope
derived first steps
mandatory boundaries
prohibited behavior
proposed alpha files
verification strategy
promotion notes
```

## Boundaries

This phase remains proposal-local.

Soul must not:

```text
register alpha skills
copy alpha files into production paths
modify workflow registries
install packages
download models
promote automatically
```

## Purpose

This phase makes alpha artifacts easier to generate and more reviewable before any implementation or promotion work begins.
