
# Phase 32 Codex Dry-Run Fixture Pack

Phase 32 adds safe fixture files for the Codex dry-run review path.

## Purpose

The controlled advisory skill loop is complete as of Phase 31.

Before using Codex on a real bounded task, Phase 32 adds deterministic fixtures that prove the dry-run review gate correctly allows safe output and blocks unsafe output.

## New commands

```bash
ruby bin/soul improve codex-fixtures
ruby bin/soul improve codex-fixtures --json
```

Aliases:

```bash
ruby bin/soul improve codex-fixture-pack
ruby bin/soul improve dry-run-fixtures
```

## Scope

Phase 32 does not:

```text
invoke Codex
send context to cloud providers
apply patches
write production implementation
enable providers
read secrets
alter runtime configuration
```

## Next phase

Phase 33 can be the first bounded Codex task using `gpt-5.5 medium`, with output reviewed locally through the handoff and dry-run review rails.
