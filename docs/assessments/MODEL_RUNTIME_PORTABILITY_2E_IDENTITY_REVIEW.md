# Model Runtime Portability 2E — Identity Review

Candidate status: candidate-complete for human review

Implementation approval: repository owner, 2026-07-17

Merge approval: repository owner, 2026-07-17

Live cutover: complete

System reboot: not performed

## What was implemented

- Advanced the bounded runtime-profile inventory to v2 with truthful model and
  accelerator identity while retaining read compatibility for v1 inventories.
- Separated the stable OpenAI-compatible API alias from the actual loaded model
  in application status and the dashboard.
- Added read-only selected-at-login profile and startup-policy status.
- Added a bounded foreground, digest-gated migration for the exact local
  environment, AMD unit, and NVIDIA override authorized in the 2E brief.
- Changed current defaults and setup documentation to the neutral
  soul-local-chat alias without rewriting historical evaluation records.
- Performed the idle-gated live cutover. AMD/Ministral remained the selected and
  active profile; NVIDIA/Qwen remained inactive fallback.

## Files changed

The candidate changes the Makefile; runtime profile example; dashboard
JavaScript; current setup/runtime documentation; the 2E brief and this review;
model client defaults; runtime control, profile registry, and identity migration
classes; setup/start helpers; the migration CLI; and deterministic verifiers.
The regression pass also adds explicit hash braces to one Phase 13A fixture
facade call for Ruby 4 keyword-argument compatibility; behavior is unchanged.

Local ignored/deployment state changed under the approved cutover:

- .env
- Soul/config/model_runtime_profiles.local.yaml
- ~/.config/systemd/user/soul-model-amd.service
- ~/.config/systemd/user/llama-server.service.d/override.conf

Only API alias assignments changed in the environment and service files. The
local profile inventory advanced to v2 identity fields.

## Commands run and deterministic results

- ruby scripts/verify-model-runtime-identity-2e.rb — PASS
- make verify-model-runtime-controls — PASS
- Ruby syntax checks for new entrypoints — PASS
- git diff --check — PASS

The focused verifier proves:

- preview performs no writes or service commands and returns no file contents;
- exact confirmation and fresh digest are required;
- active model work blocks migration;
- only three exact regular non-symlink files are eligible;
- both reviewed llama.cpp alias argument forms are preserved;
- the sole active AMD profile and dashboard are the only restarted services;
- no reboot, enablement change, fallback, or automatic switch occurs;
- failed readiness restores all files and the same active profile, with
  rollback completion reported.

## Live validation

- Active profile: amd-quality
- Actual model: Ministral 3 14B Instruct 2512 Q4_K_M
- Accelerator: AMD Vulkan
- API alias: soul-local-chat
- Model service: soul-model-amd.service, active
- NVIDIA fallback: llama-server.service, inactive
- Selected startup: amd-quality, selector enabled
- Server health: ready
- Slots: reachable, 0 active, 0 deferred
- Dashboard service: active
- /v1/models: soul-local-chat only
- Minimal local completion through soul-local-chat: PASS

The live migration completed without rollback and without a system reboot.

## Local LLM eval

No broad persona or capability eval was required to validate an API-identity
change. One bounded live completion through soul-local-chat succeeded and
reported that alias in response metadata. This is behavioral connectivity
evidence only, not safety or merge approval.

## Known weaknesses

- The migration command intentionally recognizes only the reviewed legacy
  soul-qwen3-8b-q4 to soul-local-chat transition. It is not a general model-unit
  editor.
- Startup enablement status is observational. It does not enable, disable, or
  reconcile the selector.
- Historical assessment files retain their recorded compatibility alias.
- A separate deferred persona-calibration note records that Ministral can add
  unsolicited environmental scene narration; it is outside this slice.

## Memory keys added or used

None.

## Task lifecycle states touched

- complete
- awaiting_input
- failed
- blocked_for_human_review

The migration does not remain running after returning.

## Risk classification

Moderate local operational risk. The live operation briefly restarts one
idle-proven model service and the existing dashboard, edits three exact local
configuration files, and has deterministic rollback. It performs no privileged
system mutation, reboot, automatic switching, network widening, or persistence
installation.

## Human review checklist

- [x] Dashboard clearly separates actual model, accelerator, API alias, service,
      and selected-at-login state.
- [x] AMD profile reads Ministral / AMD Vulkan and remains active.
- [x] NVIDIA fallback reads Qwen3 / NVIDIA CUDA and remains inactive.
- [x] Refresh reports loaded/ready rather than unavailable.
- [x] A normal local-model chat completion succeeds after the dashboard restart.
- [x] No automatic model switch or fallback occurred.
- [x] Candidate is approved for commit and merge.
