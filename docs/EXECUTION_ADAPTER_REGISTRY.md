# Execution Adapter Registry

Phase 55 adds the execution adapter registry.

The registry records adapter metadata for enabled and disabled execution paths.

## Commands

```bash
ruby bin/soul assess execution-adapter-registry
ruby bin/soul assess execution-adapter-registry --json
```

Aliases:

```bash
ruby bin/soul assess adapter-registry
ruby bin/soul assess adapters
```

## Enabled adapters

```text
assistant-skill-catalog
system.status
execution.history.summary
```

## Disabled / blocked adapters

```text
downloads.inspect
weather.report
cloud.providers.list
youtube.song_search
```

## Safety posture

Disabled adapters remain blocked.

Approval-required skills remain blocked before adapter execution.

The registry exposes metadata only.
