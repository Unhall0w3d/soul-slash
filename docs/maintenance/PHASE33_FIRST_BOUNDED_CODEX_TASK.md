
# Phase 33 First Bounded Codex Task

Phase 33 prepares the first real bounded Codex task package.

## Purpose

Phases 27 through 32 created the handoff, review, and fixture rails.

Phase 33 creates a local task package that can be pasted into Codex manually using `gpt-5.5 medium`.

## New commands

```bash
ruby bin/soul improve bounded-codex-task
ruby bin/soul improve bounded-codex-task --json
```

Aliases:

```bash
ruby bin/soul improve first-codex-task
ruby bin/soul improve codex-task
```

## Scope

Phase 33 does not:

```text
invoke Codex
send context to cloud providers
apply patches
write production implementation
enable providers
read secrets
alter runtime configuration
```

## Manual Codex model

```text
gpt-5.5 medium
```

## Next step after generating the package

Paste the generated `codex_prompt.md` into Codex manually, save the JSON response locally, and run `codex-dry-run-review`.
