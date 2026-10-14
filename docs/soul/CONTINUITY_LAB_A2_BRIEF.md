# Continuity Lab A2 containment and admission brief

Status: approved development continuation after A1 and the Step 3 description.
Implements and qualifies the foreground worker boundary with synthetic data;
does not authorize live inference, a service, or a production lineage.

## Selected design

Reuse installed Bubblewrap and pinned Ruby, not a VM or another daemon. Launch
one fixed repository worker per invocation. Bind only its module/script and
Ruby/system runtime read-only, plus one explicit owner-private fixture state
directory writable. Give it a private network/PID/IPC/mount namespace, private
`/tmp`, isolated `/proc`, minimal devices, cleared environment, no host home,
GPU, service sockets or inherited host file descriptors. Root and runtime paths
are never selected by model output. Do not expose arbitrary command execution.

The worker's pipe backend talks to a foreground parent through bounded JSON
frames. The parent allows only `generate` and `format_count`, fixed model/profile,
bounded input/output and call count. This stage dispatches exclusively to a
scripted fixture backend and fake counter. A route descriptor fixes future
upstream to `http://127.0.0.1:8082` and reviewed generation/template/tokenizer
paths; the worker cannot supply URLs, headers, credentials or admin operations.
Those are fixed candidate routes, not installed-version API qualification.
No HTTP transport or live inference is enabled by this stage.

Use the existing runtime control lock for a bounded dedicated test window,
rejecting every retained lease (even expired ones) without deleting records.
Holding that lock excludes participating Soul admissions/control changes for
the entire foreground invocation. Do not claim exclusion of direct/LibreChat
clients. Live use requires a separately confirmed quiet window and fresh
endpoint/profile/Core/idle evidence. Free Core, wrong model/profile, unloaded
service, pending transitions, busy/unknown/stale state all deny admission.
Snapshot assertions alone are not proof that outside clients have stopped.
The supported NVIDIA-chat Core IDs are `amd-free` (Soul-Lite), `dev` and
`music`; `free` is the distinct no-model Core. The runner itself requires the
admission gate for both `run` and `resume`. Only fixed containment, timeout and
disconnect probes may omit it, and none of those probes performs model work.

No wait queue, expiry takeover, retry, model load/unload, Core switch, cloud
fallback, scheduler or background continuation. Parent holds admission until
the child is terminated and reaped. Default wall limit 10 seconds, hard maximum
60; memory 768 MiB, CPU 30 seconds, file size 64 MiB and file descriptors 64.
Timeout, cancellation, malformed protocol or disconnect terminate/reap the
worker, preserve committed journal state, and release the lock afterward.
An interrupted model intent remains ambiguous and needs explicit review.

## Implementation ownership

Primary owns security, admission, persistence and integration. Owned additions:
`lib/soul_core/continuity_lab/{admission_gate,broker_session,pipe_backend,sandbox_runner}.rb`,
`scripts/continuity-lab-worker.rb`, A2 verifiers and review/plan documents.
Extend the existing lease store with one read-only, non-pruning snapshot method
for callers already holding its control lock. Preserve existing lease semantics
and ordinary callers. Adapt Continuity config/runtime only for the explicitly
named fixture pipe backend; it must not become a generic provider interface.

## Required evidence

- Deterministic broker/admission tests: strict protocol and bounds, deny URL/
  admin/arbitrary model requests, fixture-only routing, fresh evidence, Free
  Core/no-model preservation, shared and expired-lease refusal, control-lock
  contention, release on exception. Use temporary lease stores only.
- Actual isolated-worker checks: successful fake-core run/reopen/retrieval,
  writable fixture state, read-only code, hidden host canary/home/GPU/sockets,
  distinct network namespace and inability to reach a bounded parent-owned
  loopback canary, clean environment, timeout/cancellation/disconnect and reap.
  Verify that observed nested worker processes no longer run after cancellation;
  distinguish that result from directly reaping the parent-owned child.
  The canary listener exists only inside the foreground test and is closed in
  ensure. Its random loopback port is not a persistent network configuration.
- Run A0/A1 regressions after the runtime/config seam changes, and
  `make verify-model-runtime-controls` for the lease-store extension. Pinned
  Ruby syntax, changed-file whitespace and document-link checks.

Use the repository Ruby 4.0.7. If app sandbox blocks network namespaces, request
supported escalation for the exact fixture verifier. Record the actual host
result separately from mocked tests; fail closed if Bubblewrap is unavailable.
Do not install packages or silently run the worker without isolation.

## Remaining live decision

No production worker or live inference connection is installed. The host
currently allows unrelated direct clients to reach port 8082; neither a lease
nor an idle observation eliminates that race. Before Step 4, obtain the exact
controlled Qwen test-window scope (which clients paused, duration, retained
synthetic evidence root), or separately approve a broker-enforced endpoint
change. The controlled-window route is the initial recommendation. No network
rule/service change is hidden in this implementation approval.
