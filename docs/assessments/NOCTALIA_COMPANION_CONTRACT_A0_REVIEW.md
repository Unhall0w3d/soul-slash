# Noctalia Companion Contract — A0 Review

## Candidate

- Name: public-safe Soul/Noctalia device contract
- Risk class: moderate local-desktop integration
- Date: 2026-07-30
- Status: accepted, published, and active from the public Git source

## Implemented

- Added the public `soul.noctalia.status.v2` projection.
- Replaced UI-specific device fields with generic bounded summary/detail rows.
- Added opaque allowlisted action descriptors.
- Added `soul-noctalia connect --device DEVICE_ID`.
- Kept SSH target resolution inside Soul and out of the status document.
- Derived connectable devices from the private enrolled fleet registry.
- Added a private override registry for interactive aliases that intentionally
  differ from restricted automation aliases.
- Migrated the owner-local Noctalia plugin to v2 and the opaque connect command.
- Added a typed plugin setting for the Soul command path.
- Compacted the fleet-card region dynamically when more than four devices are
  returned, allowing Temper to fit without enlarging the flipped detail face.
- Extracted the generic UI into the public
  `Unhall0w3d/soul-noctalia` Noctalia v5 Git source.
- Kept the workstation-specific companion path in the local declarative
  `[plugin_settings."soul/overview"]` override rather than the public source.
- Replaced the owner-local discovery symlink with Noctalia's materialized Git
  source while retaining a recoverable copy of the symlink for rollback.

## Files changed

```text
bin/soul-noctalia
lib/soul_core/noctalia_device_registry.rb
lib/soul_core/noctalia_status_service.rb
scripts/verify-noctalia-companion-a0.rb
docs/soul/NOCTALIA_COMPANION_CONTRACT_A0_BRIEF.md
docs/soul/schemas/noctalia_status.schema.json
docs/assessments/NOCTALIA_COMPANION_CONTRACT_A0_REVIEW.md
Soul/private/noctalia/device_actions.json
Soul/private/noctalia/soul-overview/
```

## Commands and results

```text
ruby -c lib/soul_core/noctalia_device_registry.rb
ruby -c lib/soul_core/noctalia_status_service.rb
ruby -c bin/soul-noctalia
ruby -c scripts/verify-noctalia-companion-a0.rb
PASS

scripts/verify-noctalia-companion-a0.rb
PASS — 14 deterministic checks

git diff --check
PASS

bin/soul-noctalia status
PASS — live v2 status, Music Core, 5/5 healthy SSH devices

noctalia msg plugins disable soul/overview
noctalia msg plugins enable soul/overview
PASS — version 0.2.0 loaded, collector started

noctalia msg panel-open soul/overview:overview
PASS — panel opened; no new plugin parse/runtime error in the Noctalia log

Operator five-device layout review
PASS — after Temper joined the dynamic fleet, the compacted five-card view was
confirmed substantially improved and fully within the panel.

ruby scripts/verify-public-source.rb
PASS — complete lifecycle, no environment-specific values, and no resolved
targets exposed in the public plugin source

noctalia msg plugins source add soul git \
  https://github.com/Unhall0w3d/soul-noctalia
noctalia msg plugins update soul
noctalia msg plugins enable soul/overview
PASS — `soul/overview [soul] 0.2.0 enabled`; source and materialized checkout
both resolve to commit `3d8e963c3e3fb9f53e88ce5ffc365c308c1d0893`

noctalia msg panel-open soul/overview:overview
PASS — the Git-materialized panel opened and closed without a new Luau, parse,
or runtime error
```

## Security and lifecycle

```text
Status operation: bounded read-only projection
Connect operation: foreground terminal; execs fixed /usr/bin/ssh only after
  a validated opaque ID resolves to a reviewed private alias
Resolved target included in status JSON: no
Raw SSH alias accepted from plugin arguments: no
Maintenance or reboot authority exposed: no
Persistent service, timer, watcher, or schedule added: no
Credentials or key paths added: no
Memory keys added or used: none
Lifecycle states: complete / failed
```

## Known weaknesses and next gate

- The public plugin requires a separately installed `soul-noctalia` companion;
  this workstation uses an explicit local path until Soul has an installation
  or packaging workflow that places the command on the shell's `PATH`.
- The current device override registry is private and intentionally contains
  local device IDs and aliases. It must never be copied into the plugin repo.
- Luau behavior has live loader/render coverage but no standalone unit harness.
- Voice Presence launch remains a separate manual acceptance item.

## Local LLM eval

Not run. The candidate contains deterministic projection, validation, and UI
adapter behavior rather than conversational routing.

## Human review checklist

```text
[x] Panel renders the expected five dynamic devices without clipping
[x] Right-click still opens and closes each generic detail face
[x] Left-click opens the correct reviewed interactive SSH session
[ ] Voice Presence launch remains functional
[x] No private alias is visible in the panel or status JSON
[x] Candidate may proceed to public-repository extraction and exposure audit
[x] Public source exposure audit passes
[x] Git-source cutover loads the published commit without runtime errors
```
