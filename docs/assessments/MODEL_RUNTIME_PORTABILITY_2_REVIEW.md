# Model Runtime Portability 2A Review

## Candidate

```text
Name: Portable model runtime inventory and guarded manual switching
Risk class: Class 3 host runtime mutation
Status: candidate_complete
Human review required: yes
Date: 2026-07-16
```

## Implementation summary

Soul now accepts an optional ignored project-local YAML inventory of one to four
allowlisted model runtime profiles. The dashboard shows each profile and offers
only actions supported by verified unit and inference state. Load, unload, and
switch previews bind the exact target, unit states, active leases, slots,
deferred requests, selection, and confirmation phrase to a digest.

A switch stops the verified idle source, confirms it inactive, starts the exact
target, confirms it active, and persists only the selected profile ID. A failed
target start stops immediately, reports the completed source stop and rollback
profile, and does not retry or automatically roll back.

The existing single-profile environment remains compatible. No host unit was
created, installed, enabled, modified, started, or stopped by this candidate.
The live NVIDIA/Qwen3 service remains unchanged.

## Files changed

```text
.env.example
.gitignore
Makefile
Soul/config/model_runtime_profiles.example.yaml
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
assets/dashboard/index.html
docs/GETTING_STARTED.md
docs/MILESTONES.md
docs/ROADMAP.md
docs/soul/MODEL_RUNTIME_PORTABILITY_2_BRIEF.md
docs/assessments/MODEL_RUNTIME_PORTABILITY_REVIEW.md
docs/assessments/ALTERNATE_AMD_MODEL_ACCEPTANCE.md
docs/assessments/STRUCTURED_CAPABILITY_GAP_SIGNAL.md
docs/assessments/MODEL_RUNTIME_PORTABILITY_2_REVIEW.md
lib/soul_core/application_contract.rb
lib/soul_core/application_facade.rb
lib/soul_core/configuration_schema.rb
lib/soul_core/model_runtime_control_service.rb
lib/soul_core/model_runtime_profile_registry.rb
scripts/verify-model-runtime-portability.rb
scripts/verify-model-runtime-profile-switching.rb
```

## Commands run

```text
systemctl --user list-units --type=service --all --no-pager
systemctl --user cat llama-server.service
systemctl --user is-active soul-model-amd.service
sha256sum <pinned Vulkan llama-server> <pinned Ministral GGUF>
ruby -c lib/soul_core/model_runtime_profile_registry.rb
ruby -c lib/soul_core/model_runtime_control_service.rb
ruby -c scripts/verify-model-runtime-profile-switching.rb
node --check assets/dashboard/dashboard.js
ruby scripts/verify-model-runtime-portability.rb
ruby scripts/verify-model-runtime-profile-switching.rb
```

## Deterministic results

```text
Legacy Model Runtime Portability: passed 19/19 checks.
Model Runtime Portability 2A: passed 22/22 checks.

Covered:
- exact two-profile status and source/target preview
- stale digest and active-slot blocking
- successful switch command order and selected-profile persistence
- multiple-active conflict
- explicit load from all-unloaded state
- application facade switch route
- missing target unit fail-closed behavior
- failed target start with bounded partial-work evidence and no rollback
- traversal, symlink, duplicate ID/service, invalid default, unknown key,
  arbitrary unit, and profile-count validation
- timer-free dashboard profile rendering

Live read-only host projection after dashboard restart:
- NVIDIA fallback: active and selected
- AMD quality: unavailable because its unit is intentionally not installed
- switch: disabled
- verified NVIDIA unload: available
```

## Local LLM evaluation

```text
Not run for this slice. The AMD/Ministral behavioral evaluation was completed
in the preceding accepted slice. This candidate changes deterministic service
control and must not use LLM output as safety approval.
```

## Memory and state

```text
Durable user memory read: none
Durable user memory written: none
Skill-private memory: none
Ignored runtime state: selected profile ID only
Provider leases: existing bounded shared runtime lease records
```

## Lifecycle states

```text
complete
failed
awaiting_input
canceled (application contract)
blocked_for_human_review
```

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Watcher added: no
Scheduled task added: no
Cron job added: no
systemd unit added: no
Long-running background loop added: no
Background polling added: no
Automatic switching added: no
Automatic rollback added: no
Confirmation gate weakened: no
Arbitrary command or unit control added: no
Live provider cutover performed: no
```

## Known weaknesses

```text
- Both profiles must expose the same endpoint and model alias; the controller
  intentionally does not rewrite provider configuration.
- A target start failure leaves both profiles unloaded and requires the operator
  to review evidence and explicitly load the rollback profile.
- Service-active verification is immediate. Model readiness may remain loading
  until a later manual refresh.
- The AMD unit is not installed yet, so it remains unavailable on the live host.
- Desktop responsiveness under the persistent AMD service and the first live
  switch remain untested deployment gates.
```

## Human review checklist

```text
[ ] Confirm the profile list and selected/active labels are readable.
[ ] Confirm an unavailable unit has no Load or Switch action.
[ ] Confirm Switch preview names the current and target profiles.
[ ] Confirm the profile-bound phrase is clear.
[ ] Confirm active work and unavailable slots block unload and switch.
[ ] Confirm no automatic switching, loading, unload, retry, or rollback exists.
[ ] Confirm the shared endpoint/model-alias constraint is acceptable.
[ ] Approve or reject AMD unit deployment and first live cutover as a separate gate.
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Approved the portable profile inventory, dashboard presentation, and guarded manual switching candidate. AMD unit deployment and first live switch remain a separate gate.
Required changes: none
```
