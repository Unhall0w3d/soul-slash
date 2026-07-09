# Runtime Contract Enforcement Phase 10

## Purpose

Phase 9 added a standalone workflow handler contract validator.

Phase 10 wires contract validation into application runtime.

This creates runtime contract enforcement for registered workflow handlers.

## What changed

Application startup now validates registered workflow handlers unless explicitly disabled:

```text
SOUL_SKIP_WORKFLOW_CONTRACT_VALIDATION=1
```

The application also gains:

```bash
ruby bin/soul doctor
ruby bin/soul doctor --json
```

## Doctor output

Example:

```text
Soul Workflow Contract Health

[OK] youtube.play
     Handler: SoulCore::Workflows::YouTubePlayHandler
     Intent matching: owned
     Run: valid
     Respond: available

Summary:
1 workflows checked
1 valid
0 blocked
```

## Why this matters

A malformed registered handler should fail early.

It should not wait until a user asks Soul to do something and then collapse like a folding chair at a bad wedding.

## Verification

```bash
ruby scripts/verify-workflow-runtime-contract-enforcement-phase10.rb
```
