# Memory Core-Aware Worker A17 Review

## Candidate

An optional systemd user timer can now invoke one content-free, Core-aware A16
memory lifecycle cycle when verified pending work exists. It is a scheduled
oneshot operation, not a resident daemon.

## Files

- `lib/soul_core/memory_core_aware_worker.rb`
- `lib/soul_core/memory_core_aware_worker_deployment.rb`
- `scripts/soul-memory-lifecycle-worker`
- `scripts/verify-memory-core-aware-worker-a17.rb`
- A17 brief, Make targets, and current-state documentation

## Deterministic evidence

The verifier proves eligible-Core execution, Free/Creative skip behavior,
no-work model abstention, stable work-derived request identity, owner-private
content-free status, reviewed timer cadence, systemd hardening, plan digest
drift rejection, exact install and removal gates, and the absence of a worker
loop or listener.

```text
make verify-memory-core-aware-worker
make verify-memory-autonomous-lifecycle
make verify-memory-observation-derivation
make verify-memory-lifecycle-admission
git diff --check
```

## Authority and risk

- Risk: high because installation enables scheduled persistent execution.
- Per activation: one verified work check and at most one A16 cycle.
- Model authority: proposal only; A13 remains deterministic authority.
- Protected memory: blocked for human review.
- Free and Creative Cores: skipped without mutation.
- Deployment: not installed by repository implementation alone.

## Human gate

Review a fresh `memory-lifecycle-worker-plan`, then explicitly supply its
confirmation phrase and digest to install. Live timer cadence, Core restoration,
busy-lane behavior, and post-run ledger integrity remain human acceptance tests.

## Foreground live qualification

The exact scheduled entry point was run manually under Dev Core before timer
installation. It processed the remaining historical observation batch as one
bounded `derive_and_admit` cycle. The sole proposal was deterministically
`rejected_no_user_evidence`, so canonical memory was unchanged. A second entry
point invocation returned `no_work` without a lifecycle cycle or model request.
The observation chain remained at 38 events; derivation and admission chains
advanced to 3 valid entries each; the canonical audit remained valid at 70
events. Timer installation and scheduled cadence remain untested.
