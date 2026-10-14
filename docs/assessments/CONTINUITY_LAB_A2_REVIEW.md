# Continuity Lab A2 containment and admission review

Date: 2026-10-08
Candidate status: candidate_complete for the approved synthetic worker scope.
Human merge/release outcome: not performed. Live inference is not qualified.
Risk: security- and recovery-sensitive development boundary; no live deployment.

## Authority and outcome

The owner approved continuation after A1 and the Step 3 description.
[The A2 brief](../soul/CONTINUITY_LAB_A2_BRIEF.md) specifies this bounded scope;
[the adaptation plan](../soul/CONTINUITY_LAB_ADAPTATION_PLAN.md) keeps the later
live-Qwen, dashboard and experimental stages separate.

- One fixed Ruby worker runs inside installed Bubblewrap 0.12.0, with private
  network/PID/IPC/mount namespaces, minimal devices, cleared environment and no
  host home, GPU or service sockets. Runtime and module files are read-only;
  only its explicit owner-private fixture directory is writable on the host.
  That directory is opened without symlink traversal at its final component,
  checked against the selected inode/device, and bound through its descriptor.
- Bounded JSON pipes connect the worker to a parent-owned, fixture-only broker.
  Only `generate` and `format_count` operations are accepted. URLs, headers,
  model selection, administration and arbitrary commands are not worker inputs.
  There is no HTTP transport. The fixed future route descriptors are candidates,
  not installed llama-server API or tokenizer qualification.
- Both task execution and resume require an admission gate at the runner entry.
  The existing global runtime-control lock is held through child termination
  and direct-child reap. Any retained lease, including an expired one, blocks
  admission without pruning or rewriting it. Existing lease callers/semantics
  are unchanged; the only shared change is a read-only non-pruning inspection.
- Admission requires fresh, typed parent evidence for the exact NVIDIA profile,
  Qwen artifact name, running service, no active slot or transition, and a
  dedicated window. Allowed Core IDs are `amd-free` (Soul-Lite), `dev`, `music`;
  the distinct `free` no-model Core is denied without loading anything.
  Test snapshots are synthetic and do not attest to actual outside clients.
- Wall time defaults to 10 seconds and cannot exceed 60; address-space limit
  is 768 MiB, CPU 30 seconds, file size 64 MiB and descriptors 64. Frame/output
  budgets and nonblocking pipe handling bound communication. Timeout,
  cancellation, protocol failure or disconnect ends the worker and releases
  admission afterward. No queue, takeover, automatic retry or surviving service.
- A committed note survives a new worker invocation and explicit retrieval.
  A committed reply can be redelivered without another generation. A lost broker
  response after a recorded intent instead returns `blocked_for_human_review`
  on explicit resume; it is not silently regenerated.

## Changed paths

```text
lib/soul_core/model_runtime_lease_store.rb
lib/soul_core/continuity_lab/admission_gate.rb
lib/soul_core/continuity_lab/broker_session.rb
lib/soul_core/continuity_lab/pipe_backend.rb
lib/soul_core/continuity_lab/sandbox_runner.rb
lib/soul_core/continuity_lab/config.rb
lib/soul_core/continuity_lab/runtime.rb
scripts/continuity-lab-worker.rb
scripts/verify-continuity-lab-admission-a2.rb
scripts/verify-continuity-lab-isolation-a2.rb
docs/soul/CONTINUITY_LAB_A2_BRIEF.md
docs/soul/CONTINUITY_LAB_ADAPTATION_PLAN.md
docs/assessments/CONTINUITY_LAB_A2_REVIEW.md
docs/soul/HUMAN_REVIEW_GATE.md
skills/_template/REVIEW.md
```

The preexisting A0/A1 files and unrelated restoration changes remain uncommitted
and preserved. No commit, merge, install, model/Core switch, service mutation,
network configuration change or production state promotion was performed.
Tests created temporary synthetic stores and foreground loopback/Unix canaries,
then closed them and cleaned their test directories. No private data was used.

## Commands and observed evidence

Invoke verifiers with `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`, not the
unqualified system Ruby. The Makefile also selects repository-pinned Ruby.

| Command | Result and evidence level |
| --- | --- |
| `scripts/verify-continuity-lab-admission-a2.rb` | PASS: 14 deterministic admission/broker checks |
| `scripts/verify-continuity-lab-isolation-a2.rb` | PASS: 26 actual isolated-worker checks with a synthetic broker |
| `scripts/verify-continuity-lab-core-a0.rb` | PASS: 21 core regression checks |
| `scripts/verify-continuity-lab-recovery-a0.rb` | PASS: 149 recovery regression checks |
| `scripts/verify-continuity-lab-context-a1.rb` | PASS: 30 context regression checks |
| `scripts/verify-continuity-lab-recovery-a1.rb` | PASS: 94 recovery/boundary regression checks |
| `make verify-model-runtime-controls` | PASS: all nine constituent model-control verifiers |

Final pinned-Ruby syntax checks pass for all 19 Continuity/shared-lease Ruby
files. Links and code fences pass for the five changed documents; scoped file
whitespace and `git diff --check` also pass.

The host-isolation command ran through a supported escalation because the app
sandbox denies the socket/namespace operations it needs. It used real kernel
boundaries, not a mocked network denial. It confirmed the worker cannot reach
a parent-owned loopback listener or Unix socket, sees a different network
namespace, cannot read a synthetic host canary or host home, cannot write its
code, cannot see GPU/service sockets, and can write its selected state only.
Environment checks require exactly the expected HOME, LANG and Bubblewrap PWD.

Timeout/cancellation directly reap the parent-owned process. The verifier also
records nested process identities while alive and confirms they are absent or
no longer running afterward. That is not a claim that the parent directly
waited on every descendant; transient zombies are distinguished from running
workers. Disconnect, missing admission, retained-lease denial and interrupted
journal recovery all have actual runner-level coverage.

Shared regression coverage includes profile switching, Core orchestration,
inactive-profile deployment, Ollama deployment, Dev coordination, skill-build
coordination, selected startup, identity end-to-end and portability checks.
There was no need to rerun unrelated dashboard or semantic-memory suites.

The read-only host baseline was unchanged before/after testing:
`llama-server.service` active/running with MainPID 3058; GTX 1070 reports
8192 MiB total and 5283 MiB used; PID 3058 listens on `127.0.0.1:8082`.
No established port-8082 connections were observed at the sampled instant.
These are dated service/GPU/socket observations, not a guarantee of a quiet
future window, an artifact hash verification or a successful inference test.

`scripts/soul-codex-preflight` was inspected read-only. Its CLI/provider
reachability checks fail in the restricted execution context; that does not
prove an app outage or enlarge effective permissions. Host tests used explicit
escalation rather than treating configuration/preflight as authority.

## Review and repairs

Luna Low mapped existing admission callers read-only. Luna High owned the
bounded admission/broker verifier. Sol High reviewed the boundary read-only;
primary retained security, recovery and integration ownership.

1. Review found that an early runner relied on callers to take admission.
   Fixed: `run`/`resume` require and acquire the gate themselves. Runner tests
   reject missing admission and a retained lease before creating the store.
2. Added an expired-only lease case, verifying refusal and byte-identical
   retained evidence. An active lease cannot mask a broken stale-only check.
3. Extended cancellation evidence beyond direct-child reap to observed nested
   process identities, without claiming direct ownership of their wait status.
4. Recorded the exact A2 scope here and in the canonical gate/template rather
   than allowing A1 fake-only evidence to imply host containment or live access.

Initial host probes also identified two installed-runtime requirements:
`--disable-userns` needs explicit `--unshare-user`, and Bubblewrap sets `PWD`.
Both were corrected and covered by successful reruns. Only environment key
names were inspected during diagnosis; no environment secret values were read.

## Compatibility, lifecycle and remaining limits

The store schema remains `soul.continuity_lab.a1`. `fixture_pipe` is a distinct
explicit configuration paired only with the fixed pipe backend and `explicit_v1`
context. Its configuration digest prevents silent substitution into a different
store. Existing fake defaults and ordinary Soul chat/provider paths are intact.
No store migration, production lineage or ordinary Soul memory keys were added.

Lifecycle coverage includes complete, failed/canceled worker termination and
explicit blocked-for-human-review recovery. The worker does not keep running
after return. Candidate completion does not grant merge/release or unattended
operation. No cloud assistance, background memory promotion, timer or daemon
was introduced.

This is a fixed-code containment boundary, not a general hostile-code execution
service or proof against kernel vulnerabilities. Read-only runtime mounts are
deliberate; file/CPU/address-space limits are not a whole-host cgroup guarantee.
The control lock coordinates participating Soul callers but does not stop
LibreChat or another direct port-8082 client. A supplied snapshot is not an
enforcement mechanism for those clients. Holding the lock also temporarily
blocks cooperative runtime-control/admission operations by design.

Before Step 4: confirm the exact bounded live-Qwen test window, client-idle
arrangement, duration and retained synthetic evidence root. The recommended
route leaves the resident model/service unchanged and uses a controlled quiet
window, not a new persistent broker or network rule. Qualify the installed
formatter/tokenizer, effective model settings and at least 20 bounded cases
only within that scope. Qwen usefulness, token accuracy, live contention,
dashboard transport and human experimental acceptance remain NOT RUN.
