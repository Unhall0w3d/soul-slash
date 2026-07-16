# Model Runtime Portability Brief

```text
implementation_authorized: yes
human_authority: repository owner request on 2026-07-15
milestone: Deployment and Operations
slice: Model Runtime Portability 1
```

## Objective

Let the authenticated Soul administrator inspect, load, and unload one explicitly configured local model user service while preventing an unload during active model work. Preserve the current NVIDIA llama.cpp runtime as a rollback profile and prepare a separately installed AMD Vulkan runtime for comparative validation.

## Approved scope

- Add bounded, foreground runtime status, unload-preview, unload-execute, load-preview, and load-execute application operations.
- Control only one explicitly configured `systemd --user` service whose unit name passes a narrow allowlist.
- Require an exact confirmation phrase and matching preview digest immediately before a load or unload mutation.
- Track active local provider calls with bounded, process-owned leases in ignored shared Soul runtime state.
- Before unloading, revalidate both Soul leases and llama.cpp `/slots` state while holding the runtime control lock.
- Block unloading when a model call is active, queued/deferred work is reported, the slots endpoint is unavailable, the service state is uncertain, or the preview has changed.
- Show runtime state and manual controls in the authenticated dashboard.
- Document a parallel AMD Vulkan pilot and NVIDIA rollback path without downloading a model, replacing a binary, changing a GPU driver, or switching the live provider in this slice.

## Explicit persistence authorization

The owner previously approved the existing local `llama-server.service` and dashboard deployment. This slice may start or stop that existing, explicitly configured user service. It must not create, install, enable, or broaden a service, daemon, listener, timer, watcher, scheduled task, or background loop.

## Subsequent bounded pilot authorization

After the controller candidate passed deterministic verification, the repository owner directed work to begin on the recommended migration. That follow-on authorization permits an isolated, version-pinned Vulkan build, download and digest verification of the official Qwen3-14B Q4_K_M candidate, and bounded `llama-bench` runs. It does not authorize an additional listener, service/unit change, live endpoint change, or AMD cutover. Those remain later gates.

## Excluded scope

- No automatic idle unload or implicit load on chat submission.
- No timer, polling loop, watcher, background continuation, or unattended model switching.
- No root service control, `sudo`, system service control, arbitrary unit names, arbitrary commands, or shell interpolation.
- No forced termination of active inference.
- No driver installation, ROCm installation, replacement of the live llama.cpp binary, or provider endpoint mutation. The separately installed pilot binary and verified pilot model are governed by the bounded pilot authorization above.
- No split inference across AMD and NVIDIA.
- No cloud provider use.

## Configuration contract

The feature remains unavailable unless all required values are valid:

```text
SOUL_MODEL_RUNTIME_CONTROL=1
SOUL_MODEL_RUNTIME_SERVICE=llama-server.service
SOUL_MODEL_RUNTIME_SLOTS_URL=http://127.0.0.1:8082/slots
```

The service must be `llama-server.service` or begin with `soul-` and end in `.service`. The slots URL must be loopback HTTP. The configured provider model and endpoint remain governed by the existing portable configuration layer.

## Operations

```text
model_runtime.status
model_runtime.unload.preview
model_runtime.unload.execute
model_runtime.load.preview
model_runtime.load.execute
```

Status and previews are read-only. Execute operations are Class 3 local runtime mutations and require the exact preview phrase plus its digest. Every call terminates as `complete`, `failed`, `awaiting_input`, `canceled`, or `blocked_for_human_review`.

## Busy-state contract

A provider call acquires a lease before network transmission and releases it in an `ensure` block. A lease contains only a random lease ID, process identity, provider ID, model ID, request ID, start time, and bounded expiry; it contains no prompt or response text.

An unload preview or execution is blocked when:

- any live, unexpired Soul provider lease exists;
- any llama.cpp slot reports `is_processing: true`;
- llama.cpp metrics report processing or deferred requests;
- the active service cannot expose a trustworthy slots response;
- service state cannot be determined exactly.

Expired or dead-process leases may be removed only during a foreground lease inspection. The inspection is bounded by record and byte limits. A process-local or file lock prevents a new lease from racing an unload revalidation.

An idle conversation, persisted proposal awaiting review, stored memory record, or completed artifact preview is not active model work and does not block unload.

## Mutation behavior

Unload execution:

1. Recompute and compare the preview digest.
2. Hold the shared runtime lock so no new provider lease can start.
3. Recheck the service, leases, and server slots.
4. Run exactly `systemctl --user stop UNIT` with a bounded timeout.
5. Verify the service becomes inactive.

Load execution:

1. Recompute and compare the preview digest.
2. Hold the shared runtime lock.
3. Run exactly `systemctl --user start UNIT` with a bounded timeout.
4. Perform a bounded health check and return the observed state honestly.

No retry loop is allowed. A failed readiness check reports `failed`; it does not leave a foreground request waiting indefinitely.

## Dashboard behavior

- Show loaded, unloaded, busy, unavailable, or failed state.
- Show the configured model, backend profile label when supplied, service name, and active-work count without exposing prompts.
- Refresh once during authenticated bootstrap and only on explicit button activation afterward.
- Preview before revealing the confirmation field.
- Disable unload when active work or uncertain state is reported.
- Keep deterministic dashboard features available while the model is unloaded.
- Chat submission while unloaded follows the existing truthful provider-unavailable behavior and does not automatically start the service.

## Deterministic acceptance

- Provider leases exist only during a bounded provider call and are cleaned after success, error, and timeout.
- Dead and expired leases do not permanently strand runtime control.
- Unload blocks for live leases, active slots, deferred requests, unreachable slots, and changed previews.
- Load/unload command arguments are fixed and never pass through a shell.
- Only the configured allowlisted user unit can be controlled.
- Execute operations require exact confirmation and digest revalidation.
- The dashboard has no timer, polling, auto-load, or auto-unload primitive.
- Existing conversation, artifact, skill, authentication, and dashboard tests remain passing.

## Human review outcome

```text
Outcome: approved for candidate implementation
Reviewer: repository owner
Date: 2026-07-15
Decision summary: Begin the recommended reversible AMD migration and safe dashboard model-control work.
```
