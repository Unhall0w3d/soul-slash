# Model Runtime Portability 2C — First Guarded AMD Live Switch Review

## Candidate

```text
date: 2026-07-16
status: candidate_complete
risk class: Class 3 — operator-authorized local service lifecycle change
human review required: yes
```

## Authorized operation

One guarded NVIDIA-to-AMD switch through Soul's existing preview, state digest,
exact-confirmation, active-work, slot-idle, and control-lock boundary. One
guarded NVIDIA recovery is authorized only if cutover acceptance fails.

## Evidence

### Pre-switch state

```text
active/selected profile: nvidia-fallback
target profile: amd-quality, loaded and inactive
active profiles: 1
active work: 0
leases: 0
slots: 1 reachable, 0 active
endpoint health: ready
idle certain / can switch: true / true
NVIDIA compute process: llama-server, 5,296 MiB
AMD unit state: inactive/dead, static
```

The controller generated exact confirmation
`SWITCH_MODEL_RUNTIME_TO_AMD_QUALITY` and preview digest
`fc504976bd87fd45622a5c055042ee2beb90c488b2ee27afc87de94b41417cac`.
Execution re-observed the state under the control lock, matched that digest,
stopped only `llama-server.service`, started only `soul-model-amd.service`, and
persisted only profile ID `amd-quality`.

### Post-switch state

```text
active/selected profile: amd-quality
active profiles: 1
active work: 0
leases: 0
endpoint: http://127.0.0.1:8082/v1
health: ready
slots: 1 reachable, 0 active
advertised alias: soul-qwen3-8b-q4
AMD VRAM: 12,200,681,472 / 17,163,091,968 bytes
NVIDIA compute processes: none
NVIDIA unit: inactive/dead, enabled (unchanged rollback/startup behavior)
AMD unit: active/running, static (not enabled)
automatic load/unload/switch: false / false / false
```

The first bounded readiness observation found the AMD endpoint healthy and idle.
The controller's final live projection reports `state: loaded`, `can_unload:
true`, and `can_switch: true`. No rollback criterion was met, so the authorized
recovery operation was not used and AMD remains active for human review.

### Integrity evidence

```text
NVIDIA unit SHA-256: bd1b18d7af63213ee2ed63bba70bba514677941eaa2744a4e8ffa84d2dfa4e21
NVIDIA drop-in SHA-256: c28ade127f915dd3f4042a82a27538325c7d708c58d06d36db2423d3fee1ad3c
AMD unit SHA-256: c1e690eb3c07a3f393ad45f3a4b067303833949eb7974df5df7fcff66472dbc7
AMD server SHA-256: c7a15d4eaef92e63869db6725f4976943a194ca5741933ed45b9c7ebecf78e68
Ministral model SHA-256: 824e0f3373e69b84f2cae46fdcb9bd1ebc6ab3bfc7acc125d818b7b8178cc613
```

All values matched the pre-switch and approved 2B inputs.

## Files changed

```text
docs/soul/MODEL_RUNTIME_PORTABILITY_2C_LIVE_SWITCH_BRIEF.md
docs/assessments/MODEL_RUNTIME_PORTABILITY_2C_LIVE_SWITCH_REVIEW.md
docs/MILESTONES.md
docs/ROADMAP.md
```

No runtime implementation, provider configuration, unit, `.env`, Caddy, UFW,
model, binary, or dashboard source file changed in this slice.

## Commands and results

```text
ruby scripts/verify-model-runtime-profile-switching.rb                 pass
ruby scripts/verify-model-runtime-profile-deployment.rb                pass
ruby scripts/run-phase13b-local-model-acceptance.rb                    pass
ruby scripts/verify-phase13b-local-model-dashboard-acceptance.rb       pass
ruby scripts/verify-live-persona-contract.rb                           pass
ruby scripts/verify-model-runtime-portability.rb                       pass
git diff --check                                                       pass
```

The live acceptance completed 20/20 model turns in 95.46 seconds. All responses
were nonempty, all 20 response hashes were unique, all six continuity probes
passed, and the local-only provider used no cloud fallback. Synthetic transcript
content was not retained.

## Memory keys

```text
reads: none from durable user memory
writes: none to durable user memory
runtime state: shared selected_profile.json only after successful controller mutation
```

## Lifecycle states touched

```text
complete
failed
awaiting_input
blocked_for_human_review
```

No process remains running to wait for review. The selected model service may
remain active because that exact persistent runtime lifecycle was authorized by
the 2C brief; neither service is enabled by this gate.

## Safety and persistence check

```text
Persistent service added: no (the approved 2B unit is reused)
Service lifecycle mutation: approved, bounded, and controller-gated
Service enablement added: no
Automatic switching/failover added: no
Watcher/timer/scheduled task added: no
Background polling added: no
Confirmation or active-work gate weakened: no
Provider or LAN configuration changed: no
Cloud request made: no
Durable memory changed: no
```

## Known weaknesses

- The unchanged compatibility alias still says `soul-qwen3-8b-q4` even though
  the active profile is Ministral. The profile label is authoritative in the
  dashboard, but a neutral alias should be considered in a later coordinated
  provider-and-rollback change.
- AMD is intentionally static and NVIDIA remains enabled. After a user-session
  restart, NVIDIA will start while the persisted selection may still say AMD.
  Explicit selected-profile startup semantics require a separate reviewed gate.
- This gate validates Soul behavior and GPU placement, not simultaneous desktop,
  gaming, music-generation, vision, or sustained thermal workloads.
- Ministral's previously recorded verbosity and occasional unsupported UI-label
  invention remain model-quality concerns rather than cutover blockers.

## Human review checklist

```text
[x] Review pre-switch idle and integrity evidence
[x] Review controller preview phrase and digest-bound execution
[x] Review AMD readiness, sole-active profile, endpoint, and GPU evidence
[x] Review bounded Soul behavioral acceptance and deterministic regressions
[x] Confirm NVIDIA remains a byte-identical manual rollback
[x] Confirm the AMD unit was not enabled and no automation was added
[x] Approve AMD remaining the active local runtime
```

## Human review outcome

```text
Outcome: approved
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Approved the guarded live AMD cutover and AMD remaining active; startup policy remains a separate gate.
Required changes: none
```
