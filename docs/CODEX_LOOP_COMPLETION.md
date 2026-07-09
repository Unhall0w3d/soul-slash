
# Codex Loop Completion

The Codex loop completion assessment records the first bounded Codex loop as a finished milestone.

## Completed loop

```text
generate bounded task package
review prompt
repair prompt
send bounded prompt to Codex manually
save JSON response locally
dry-run review response
apply reviewed documentation through deterministic overlay
verify and commit
```

## Command

```bash
ruby bin/soul assess codex-loop
ruby bin/soul assess codex-loop --json
```

Aliases:

```bash
ruby bin/soul assess codex-loop-completion
ruby bin/soul assess bounded-codex-loop
```

## What complete means

Complete means Soul has a working Codex-assisted review path where Codex output remains advisory until reviewed locally and applied through deterministic human-controlled work.

It does not mean Codex can run automatically.

It does not mean patches can be applied automatically.

It does not mean generated task artifacts should be committed.

## Local artifacts

Generated task artifacts under `Soul/codex/` are not required for completion.

Remove them when finished unless deliberately retained for inspection.

## Next optional tracks

```text
doctor surface expansion
documentation registry refresh
second bounded Codex task
local STT assessment
```
