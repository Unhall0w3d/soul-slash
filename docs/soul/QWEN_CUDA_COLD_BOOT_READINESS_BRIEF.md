# Qwen CUDA Cold-Boot Readiness — Candidate Brief

```text
implementation_authorized: yes, by owner request to address the observed startup cause
persistent_selector: existing soul-model-runtime-selected.service only
new_service_or_timer: no
model_unit_change: no
live_model_transition: no
reboot: no
human_review_required_before_merge_or_deployment: yes
```

## Observed fault

On the September 22 boot, the user manager started the selected Qwen service at
23:38:12 EDT. Qwen reported that no CUDA device was detected and continued on
CPU. The host's `/dev/nvidia0` and `/dev/nvidiactl` nodes were created at
23:38:13.798 EDT. The existing selector checked only whether the service was
active, so it reported success while Qwen ran on CPU.

This is a targeted amendment to
[Model Runtime Portability 2D](MODEL_RUNTIME_PORTABILITY_2D_SELECTED_STARTUP_BRIEF.md).
Its zero-wait and no-automatic-stop rules remain in force for other profiles.
The approved repair request permits bounded wait and exact cleanup for the
site's reviewed `nvidia-fallback` / `llama-server.service` Qwen profile only.

## Candidate behavior

Within the existing one-shot selector and shared model-runtime control lock:

1. Preserve Free Core, selection validation, conflicting-service, and already
   active profile behavior.
2. If the selected Qwen service is already active, verify its `MainPID` has
   at least 4,500 MiB allocated on the CUDA-visible NVIDIA GPU. If not,
   return `blocked_for_human_review` without changing the service.
3. Before starting inactive Qwen, wait at most 15 seconds for both NVIDIA
   character device nodes and a successful `nvidia-smi --id=0` UUID query.
   If unavailable, return `failed` without starting a service.
4. Start the selected unit once. Wait at most 30 seconds for the service
   `MainPID` to hold at least 4,500 MiB on that same GPU UUID.
5. If placement is not established, stop only the Qwen unit started by this
   selector invocation, check that it is inactive, and report whether cleanup
   succeeded. Do not start a fallback or retry Qwen.
6. Report `complete` only after the exact Qwen process and GPU allocation
   are verified. Other selected profiles keep their prior startup path.

The guard uses the existing `nvidia-smi` utility and no new service, daemon,
timer, network listener, unit definition, or background continuation. Each
command remains bounded; waits use a monotonic deadline and attempt cap.
The active model is never restarted as part of installation. A future boot is
required to qualify the original race end to end; no reboot is authorized here.

## Acceptance

- Deterministic tests cover late device nodes, delayed GPU allocation, missing
  nodes, CPU fallback cleanup, failed cleanup, preexisting CPU-backed Qwen,
  and a foreign GPU allocation.
- Existing selected-startup and relevant model runtime tests pass.
- Read-only live checks confirm the GPU UUID, Qwen `MainPID`, and allocation
  parser against the installed host.
- Review exact diff, approve merge/deployment separately, and observe a
  subsequent cold boot before claiming end-to-end resolution.

## Human review outcome

```text
Outcome: approved for merge
Reviewer: repository owner
Date: 2026-09-25
Decision summary: Owner approved the Qwen startup changes for merge. Cold-boot qualification remains pending; no reboot was requested.
```
