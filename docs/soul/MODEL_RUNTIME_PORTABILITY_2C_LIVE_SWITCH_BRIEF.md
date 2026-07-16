# Model Runtime Portability 2C — First Guarded AMD Live Switch Brief

```text
implementation_authorized: yes
service_lifecycle_authorized: yes
human_authority: repository owner approval on 2026-07-16
milestone: Deployment and Operations
slice: Model Runtime Portability 2C
human_review_required: yes
```

## Objective

Perform one operator-authorized, foreground NVIDIA-to-AMD runtime switch through
Soul's existing model-runtime controller, validate the already accepted
Ministral/Vulkan profile on Soul's production loopback endpoint, and leave AMD
selected only if every operational acceptance check passes.

This is an operational cutover gate. It does not enable either service, create
auto-start behavior, modify provider configuration, or add automatic failover.

## Explicit service-lifecycle authorization

The owner authorizes exactly one attempted controller operation:

```text
switch: nvidia-fallback -> amd-quality
confirmation: SWITCH_MODEL_RUNTIME_TO_AMD_QUALITY
```

The controller must first prove that exactly one source profile is active, the
AMD target is installed and inactive, the shared `/slots` endpoint is
reachable, and no active lease, processing request, or deferred request exists.
The preview digest must still match when execution begins.

If the switch or any acceptance check fails, this brief also authorizes one
bounded recovery operation through the same controller:

```text
switch: amd-quality -> nvidia-fallback
confirmation: SWITCH_MODEL_RUNTIME_TO_NVIDIA_FALLBACK
```

If the AMD start fails before any profile is active, recovery may instead use
the controller's explicit `load nvidia-fallback` preview, digest, and exact
confirmation. Direct unguarded service control is not the normal path.

## Pinned scope

```text
source service: llama-server.service
target service: soul-model-amd.service
provider endpoint: http://127.0.0.1:8082/v1
health endpoint: http://127.0.0.1:8082/health
slots endpoint: http://127.0.0.1:8082/slots
target device: Vulkan0 / RX 6900 XT
target model: Ministral 3 14B Instruct 2512 Q4_K_M
target compatibility alias: soul-qwen3-8b-q4
```

The binary, model, hashes, and exact unit command remain those approved and
installed in 2B. Their files and the existing NVIDIA unit/drop-in must remain
byte-identical through this gate.

## Foreground bounds

```text
controller switch attempts: 1
recovery attempts if needed: 1
startup readiness deadline: 180 seconds
readiness probe interval: at most 3 seconds
behavioral requests: bounded by existing acceptance scripts
cloud fallback: prohibited
background continuation: prohibited
```

Any readiness probing occurs only inside the foreground invocation and stops at
success, failure, cancellation, or the deadline. No watcher, timer, service
enablement, or unattended retry is introduced.

## Acceptance sequence

1. Record Git state, unit hashes, service states, controller status, active
   leases/slots, endpoint health, and available GPU observations.
2. Run the deterministic model-runtime deployment and switching verifiers.
3. Obtain a fresh controller preview for `amd-quality`; require `can_switch`,
   `idle_certain`, zero active work, the exact phrase, and a 64-character digest.
4. Execute the digest-bound switch through `ModelRuntimeControlService`.
5. Wait boundedly for `/health` to become ready and `/slots` to report idle.
6. Confirm AMD is the sole active and selected profile, NVIDIA is inactive, and
   neither unit is enabled by this operation.
7. Run bounded Soul conversation/provider acceptance against the unchanged
   production endpoint with cloud fallback disabled.
8. Record AMD VRAM when exposed through read-only sysfs and confirm the NVIDIA
   runtime process no longer occupies its GPU.
9. Recheck unit/configuration hashes and dashboard runtime projection.
10. On any failed operational criterion, execute the authorized guarded
    recovery and verify NVIDIA health before returning a failed lifecycle.

## Required successful result

- AMD is the only active model profile and is the persisted selection.
- The production loopback endpoint is healthy, has one idle slot, and advertises
  the compatibility alias required by the unchanged Soul provider.
- Soul completes deterministic provider/runtime regressions and a bounded live
  conversation evaluation without cloud fallback.
- NVIDIA is inactive and remains available as the reviewed manual rollback.
- AMD remains static/unenabled; no automatic startup or switching is added.
- Dashboard status reflects the live AMD profile without a dashboard restart.
- All pinned runtime/unit files remain byte-identical.

## Failure result

The gate returns `failed` or `blocked_for_human_review`, records the exact failed
criterion, performs at most the authorized recovery operation, and verifies the
restored NVIDIA endpoint. It must not silently leave both profiles active or no
profile active.

## Explicit exclusions

- No service enablement, login startup, automatic failover, or automatic model
  selection.
- No `.env`, Caddy, UFW, dashboard-service, NVIDIA unit, or AMD unit mutation.
- No model/binary download, build, package, driver, permission, or root action.
- No LAN listener, cloud request, tool execution, host mutation, or memory
  promotion based on model output.
- No concurrent GPU workload benchmark or music/image model deployment.

## Human review outcome

```text
Outcome: approved for one guarded live switch with bounded recovery
Reviewer: repository owner
Date: 2026-07-16
Decision summary: Proceed from the reviewed inactive AMD deployment to the next gate.
```
