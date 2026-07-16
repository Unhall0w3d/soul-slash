# Model Runtime Portability 2 — Manual Profile Switching Brief

```text
implementation_authorized: yes
human_authority: repository owner direction on 2026-07-16
milestone: Deployment and Operations
slice: Model Runtime Portability 2A
human_review_required: yes
```

## Objective

Extend the accepted single-service runtime controller into a portable,
operator-controlled profile boundary. Soul may show a configured NVIDIA rollback
profile and AMD quality profile, load either while all profiles are unloaded,
unload the one active profile, or switch between them only after an unchanged
preview and exact human confirmation.

This candidate does not cut over the live provider, install a unit, or start the
AMD service. Host deployment and the first live switch remain a separate human
review gate.

## Approved persistence boundary

The owner explicitly approved development toward an AMD systemd user-service
profile while preserving the existing NVIDIA service. This implementation may:

- control an already installed, explicitly configured, allowlisted systemd user
  service through bounded `start` and `stop` commands;
- persist the selected profile ID in ignored Soul runtime state after a verified
  load or switch;
- provide portable configuration and deployment documentation for a later AMD
  user unit.

This candidate must not create, install, enable, start, stop, or modify the AMD
unit on the host. It must not edit the existing NVIDIA unit or drop-in. Those
host mutations require review of this candidate and a separate deployment gate.

## Shared provider contract

All configured profiles must expose the same already configured local provider
endpoint, slots endpoint, and model alias. Profiles vary only by human-readable
identity and allowlisted systemd user-service name. This keeps Soul's provider
configuration stable during a manual switch and avoids runtime `.env` rewrites.

The private, ignored profile file uses:

```yaml
schema_version: soul.model_runtime_profiles.v1
default_profile: nvidia-fallback
profiles:
  - id: nvidia-fallback
    label: NVIDIA fallback
    service: llama-server.service
  - id: amd-quality
    label: AMD quality
    service: soul-model-amd.service
```

The file must be a regular, non-symlink file beneath the project root, at most
32 KiB, with one to four profiles. IDs and services are narrowly validated,
services are unique, unknown keys fail closed, and arbitrary commands are never
accepted. Without a profile file, the accepted single-profile environment
contract remains compatible.

## Operations

```text
model_runtime.status
model_runtime.load.preview(profile_id optional)
model_runtime.load.execute(profile_id optional, confirmation, expected_digest)
model_runtime.unload.preview(profile_id optional)
model_runtime.unload.execute(profile_id optional, confirmation, expected_digest)
model_runtime.switch.preview(profile_id required)
model_runtime.switch.execute(profile_id required, confirmation, expected_digest)
```

Status and previews are read-only. Execute operations are Class 3 host runtime
mutations. Every call terminates in `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review` and never continues in the background.

## Safety behavior

- At most one configured profile may be active. Multiple active units create a
  conflict that blocks every mutation.
- Load requires every configured profile to be inactive.
- Unload targets exactly the one active profile.
- Switch requires exactly one active source and one different inactive target.
- Unload and switch revalidate Soul provider leases, llama.cpp slots, processing
  metrics, deferred work, unit states, and the exact preview digest while holding
  the shared runtime-control lock.
- An unreachable slots endpoint, uncertain unit, active request, changed target,
  changed selection, or changed service state blocks before mutation.
- Switch stops the verified source, verifies it inactive, starts the target, and
  verifies it active. If target start fails, execution stops and reports the
  completed source stop; it does not retry, auto-rollback, or continue unseen.
- No forced termination, automatic failover, automatic loading, automatic idle
  unload, polling timer, watcher, queue, scheduler, or background loop is added.
- Chat while unloaded remains an honest provider-unavailable result.

## Dashboard behavior

- Show every configured profile, its unit state, and selected/active identity.
- Keep the existing loaded, unloaded, busy, loading, uncertain, and unavailable
  aggregate state.
- Offer Load only when all profiles are safely inactive.
- Offer Switch only for an inactive target while one other profile is verifiably
  idle and active.
- Offer Unload only for the active, verifiably idle profile.
- Every action opens the existing preview dialog, shows source/target scope, and
  requires its exact profile-bound confirmation phrase.
- Refresh once during authenticated bootstrap and only manually afterward.

## Bounds

```text
profiles: 1..4
profile file: 32 KiB
systemctl command timeout: 12 seconds
HTTP request timeout: 2 seconds per slots/metrics/health observation
retries: 0
background continuation: prohibited
```

## Deterministic acceptance

- Legacy single-profile configuration remains passing.
- Profile configuration rejects symlinks, traversal, duplicate IDs/services,
  unknown keys, invalid defaults, arbitrary units, and more than four profiles.
- Status exposes bounded redacted profile state without paths or commands.
- Load, unload, and switch require exact profile-bound confirmation and unchanged
  digest.
- Live leases, active slots, deferred work, unreachable slots, uncertain units,
  and multiple active profiles block before mutation.
- Failed target start reports the stopped source and performs no automatic retry
  or rollback.
- Successful switch persists only the selected profile ID.
- Dashboard remains timer-free and uses explicit manual actions.
- Existing runtime, conversation, dashboard, and Phase 13 regressions pass.

## Human review outcome

```text
Outcome: approved for candidate implementation
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Begin the recommended AMD profile and guarded manual switching work; actual provider cutover remains separately reviewed.
```
