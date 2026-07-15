# Conversational Soul Phase 12A Portable Typed Configuration

## Candidate status

```text
candidate_complete
human_merge_review_required
```

Candidate-complete means ready for human review, not approved for merge, release, deployment, or unattended use.

## Implementation summary

- adds one canonical schema for 21 interface-relevant settings;
- implements typed, source-aware resolution with CLI override, process environment, `.env`, and safe-default precedence;
- adds a bounded, non-interpolating `.env` reader that does not mutate process environment;
- redacts cloud credentials while reporting secret presence and source;
- adds read-only `config show`, `config explain`, and `config validate` commands;
- supplies a compatibility environment projection to Chat and the existing provider registry;
- preserves compatibility aliases and explicit cloud opt-in;
- reserves inert loopback-only dashboard host and port settings;
- updates the portable public `.env.example` and canonical documentation;
- adds no listener, dashboard, service, daemon, watcher, scheduler, polling, provider probe, configuration writer, or memory store.

## Files changed

```text
.env.example
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE12A_PORTABLE_TYPED_CONFIGURATION.md
docs/soul/PHASE12A_PORTABLE_TYPED_CONFIGURATION_BRIEF.md
docs/soul/PORTABLE_TYPED_CONFIGURATION.md
lib/soul_core/app.rb
lib/soul_core/configuration_command.rb
lib/soul_core/configuration_resolver.rb
lib/soul_core/configuration_schema.rb
lib/soul_core/dotenv_reader.rb
lib/soul_core/phase12a_portable_typed_configuration_assessor.rb
scripts/verify-phase12a-portable-typed-configuration.rb
```

## Commands run

```text
ruby bin/soul config validate
ruby bin/soul config explain dashboard.bind_host
ruby bin/soul assess phase12a-portable-typed-configuration --json
ruby bin/soul assess phase12a-portable-typed-configuration
ruby scripts/verify-phase12a-portable-typed-configuration.rb
find lib scripts bin -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
ruby bin/soul assess repo-curation --json
git diff --check
```

## Deterministic test results

```text
PASS: 18/18 Phase 12A checks.
PASS: local `.env` validates without exposing its values.
PASS: Phase 11A, 11B, 11C, and 11D regressions.
```

Coverage includes safe defaults, source precedence, cross-layer aliases, types, ranges, secret redaction, custom credential names, unsafe overrides, non-executing `.env` values, malformed input, project bounds, symlinks, provider compatibility, cloud opt-in, loopback binding, CLI lifecycle behavior, schema metadata, caller-environment preservation, and public-template portability.

## Local LLM eval results

```text
Not required and not run.
```

Phase 12A is deterministic configuration infrastructure. Configuration values must not be sent to a model for evaluation.

## Memory keys

```text
Reads: none
Writes or updates: none
Forget behavior: not applicable
```

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

No process remains alive after configuration output returns.

## Risk classification

```text
Class 0: Read-only local or conversational
```

Runtime configuration inspection and invocation-scoped overrides do not mutate local configuration or process environment.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Network listener added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
launch agent added: no
Windows service added: no
Long-running background loop added: no
Background polling added: no
Configuration writer added: no
Provider probe added: no
Secret CLI input added: no
Confirmation gate weakened: no
Cloud opt-in weakened: no
Skill-private memory store added: no
```

## Known weaknesses

- Configuration inspection and Chat use the typed resolver now; legacy commands still consume the existing environment surface during the bounded migration.
- `.env` values are literal and intentionally do not support multiline values, interpolation, shell expansion, or inline-comment parsing.
- The configuration surface is read-only; guided `.env` editing remains a future explicitly approved feature.
- Secret presence is visible, but credential validity is not tested because Phase 12A performs no provider probe.
- Dashboard host and port are inert until the separately approved foreground loopback dashboard phase.
- Restart metadata is currently false because the CLI resolves once per foreground invocation; later deployment may require different restart semantics.

## Human review checklist

```text
[ ] Matches the approved Phase 12A brief
[ ] Precedence and alias behavior are appropriate
[ ] Types, ranges, and defaults are appropriate
[ ] Public configuration output cannot expose secrets
[ ] Public `.env.example` is portable
[ ] Cloud opt-in remains explicit
[ ] Dashboard settings remain loopback-only and inert
[ ] Existing Chat/provider compatibility is preserved
[ ] No configuration or process-environment mutation occurs
[ ] No listener, service, watcher, or background behavior exists
[ ] Deterministic tests are meaningful
[ ] Phase 11 regressions pass
[ ] Known weaknesses are acceptable
[x] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: approved for merge
Reviewer: human owner
Date: 2026-07-14
Decision summary: Human owner explicitly approved merge after reviewing the candidate summary and validation results.
Required changes: none
```
