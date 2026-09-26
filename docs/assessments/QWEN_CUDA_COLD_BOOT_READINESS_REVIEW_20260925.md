# Qwen CUDA Cold-Boot Readiness — Candidate Review

```text
Candidate status: candidate_complete
Outcome: pending human review
Branch: codex/qwen-cuda-startup-readiness
Risk: consequential persistent startup behavior
```

## Scope and cause

The September 22 boot journal placed Qwen's CUDA initialization at
23:38:12 EDT. The host created `/dev/nvidia0` and `/dev/nvidiactl` at
23:38:13.798 EDT. Qwen continued on CPU, while the existing selected-profile
selector reported success because `llama-server.service` was active. The
repair is confined to the existing selected-startup controller and its
verifier. It changes no model unit, installed selector unit, model binary,
profile selection, or running service.

The candidate follows
[Qwen CUDA cold-boot readiness brief](../soul/QWEN_CUDA_COLD_BOOT_READINESS_BRIEF.md).
It specifically amends the earlier 2D selector's zero-wait and no-stop
conditions for the site's `nvidia-fallback` Qwen service. Other profiles
retain those conditions.

## Behavior

- For inactive Qwen, wait at most 15 seconds for both NVIDIA character device
  nodes and the CUDA-visible GPU UUID to be queryable, then issue one
  `systemctl --user start llama-server.service`.
- Require the service's actual `MainPID` to hold at least 4,500 MiB on the
  same GPU within 30 seconds. This threshold is below the observed 5,296 MiB
  Qwen allocation and matches the existing Whisper handoff qualification.
- If placement is not established, stop only the Qwen unit this invocation
  started, verify its state, and report failure. A failed cleanup is explicit.
- If Qwen was active before the selector ran, perform one read-only placement
  check; if it is CPU-backed, return `blocked_for_human_review` without
  stopping it.
- Free Core and AMD selection keep their existing behavior. No retries,
  fallback model, background continuation, reboot, or new persistence are
  added.

## Evidence

Deterministic:

```text
ruby scripts/verify-model-runtime-selected-startup.rb          PASS
ruby scripts/verify-model-runtime-profile-switching.rb        PASS
ruby scripts/verify-model-runtime-temporary-release.rb        PASS
ruby scripts/verify-whisper-runtime-handoff.rb                PASS
ruby -c lib/soul_core/model_runtime_selected_starter.rb       PASS
git diff --check                                               PASS
```

Read-only host observation on September 25:

```text
llama-server.service ActiveState=active, MainPID=484511
nvidia-smi --id=0 UUID=GPU-92d94102-e241-1a40-62c5-832d60874aab
compute allocation: PID 484511, same UUID, 5296 MiB
candidate guard read-only identity and allocation probes: PASS
live profile: nvidia-fallback / llama-server.service / NVIDIA CUDA
```

The host's NVIDIA device nodes are not represented in udev's device database;
`udevadm wait --initialized=no` timed out while the nodes existed.
Therefore the candidate uses direct bounded device and driver checks.

## Boundaries and remaining qualification

The candidate is isolated in a separate worktree. No live startup code or
service has been changed by this review, and no boot was performed. The
deterministic suite proves decision logic; the host read proves current Qwen
placement and query shape. The original cold-boot race remains to be qualified
after an approved merge and a future normal boot.

A very late driver start beyond 15 seconds will leave Qwen unstarted and
report a visible failure. If the exact cleanup command itself fails, the
controller reports that active CPU-backed Qwen may remain; it does not claim
success. A service started outside Soul's control lock remains outside this
selector's cleanup authority.

## Human review checklist

```text
[x] Exact Qwen profile and selected unit only
[x] Free Core and AMD paths retain prior policy
[x] No new service, daemon, timer, network listener, or model unit change
[x] No automatic fallback or restart
[x] Bounded readiness and placement checks
[x] Deterministic CPU fallback and cleanup failure coverage
[x] No credentials, private memory, or projection changes
[ ] Owner approves merge and next-boot deployment
[ ] Subsequent cold boot verifies NVIDIA placement end to end
```

## Human review outcome

```text
Outcome: pending
Reviewer:
Date:
Decision summary:
```
