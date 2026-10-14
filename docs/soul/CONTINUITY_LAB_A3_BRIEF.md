# Continuity Lab A3 live-Qwen qualification brief

Status: owner approved the proposed controlled test window on October 8, 2026.
Extends A2 for a bounded development qualification, not deployment or release.

## Scope and limits

Implement the fixed host-side Qwen transport, fresh host observation, explicit
qualification-only pipe profile, deterministic transport checks and a 20-case
foreground harness. Use the existing NVIDIA Qwen service unchanged. Maximum
live window: 1,200 seconds starting with the retained harness run; at most 20
cases, 6 generation calls per case and 60 calls total, 768 output tokens per
call, 60 seconds per worker/case and 30 seconds per HTTP generation. Stop the
run on an infrastructure/admission failure; record behavioral failures without
repairing outputs or switching models. No inference outside that harness.

Operator has approved keeping other Qwen clients idle. This is a controlled
window, not enforced exclusion of direct clients. Hold the A2 control lock for
each worker, observe Core/profile/PID/template/slot before generation, and stop
on changes, busy or uncertain state. Check idle after each case. Never stop,
load, switch or restart services, alter network rules, or create a scheduler.

Retain synthetic-only evidence in a newly created owner-private directory:
`Soul/runtime/qualification/continuity-lab-a3-<timestamp>`. Refuse reuse. No Git
addition, upload, ordinary Soul memory import or automatic retention deletion.
Existing backup policies may include this directory. No user secrets or private
corpus content enter the model. The source archive remains unchanged.

## Integration contract

Reuse the A2 Bubblewrap worker and gate. Add explicit `qwen_run`/`qwen_resume`
modes and a distinct `qwen_pipe` configuration. Keep existing fake modes intact.
The worker still cannot choose endpoints, settings, shell commands or host paths.

The host broker renders the existing explicit context envelope through the
installed `/apply-template` with thinking disabled, tokenizes the exact result
using `/tokenize`, and sends those token IDs to native `/completion`. Fixed
loopback origin only; no proxy, redirects, cloud, authentication or admin route.
Require 3,072 or fewer actual input tokens plus 768 output and 256 margin within
the resident 4K window; no truncation. Retain template/model/build fingerprints,
exact prompt/token IDs, sampler/settings, raw outputs, timings and usage.
Check reported input count/truncation against the submitted count.

The A1 journal's byte-based packing counter remains explicitly a fixture
counter. Its eligible-source and whole-group packing decisions are preserved;
the live token gate is an additional independently enforced ceiling, not a
claim that A1 has become an exact-token optimizing packer. Bind live receipts
to envelope digest and call index. Replay remains offline and deterministic.
Real-token overflow fails closed and preserves an unresolved intent for review;
it must not invoke generation or be silently repaired/retried.

Use JSON-object constrained output only, not hidden semantic action repair.
Freeze seed and sampling parameters. These choices are a recorded condition,
not evidence that model behavior is deterministic or that optional notes help.

## Required evidence and ownership

Primary owns transport, host observation, journal/profile changes, boundaries,
live execution and review. Delegate bounded mapping or review only. Preserve
the dirty shared tree; no commit/merge is authorized.

- Deterministic tests cover endpoint allowlist, no redirects/proxy/fallback,
  payload and response limits, identity drift, token ceilings and usage mismatch,
  unavailable backend, fail-closed admission and original fake compatibility.
- Rerun A0/A1 suites for runtime/config changes, A2 admission and actual isolation
  for runner/worker changes, and targeted A3 tests. No ordinary provider code
  changes are planned; broaden regressions only if shared behavior changes.
- Live cases cover reply/wait, note write/read/search, optional no-note behavior,
  explicit corpus retrieval, fresh-process context isolation, correction,
  tombstones and multi-step/rollover. Keep observed utility distinct from the
  deterministic tests that enforce tool/permission and recovery boundaries.
- Record real timings, input/output counts, sampled GPU allocation, failures and
  untested items. Preserve ambiguous outcomes. Update the adaptation plan,
  canonical human-review gate and review template before handoff.

## Recovery and next gate

First window completed: all 20 cases scored, 7 passed. The retained baseline
uses the original shorthand prompt. A clearer `qwen_envelope_v2_explicit_examples`
contract was prepared afterward and tested deterministically before proposing
a comparison. See the [original A3 review](../assessments/CONTINUITY_LAB_A3_REVIEW.md).

The owner subsequently instructed "please proceed" in response to the explicit
second 20-case comparison proposal. That authorizes one new v2 batch with the
same 1,200-second/60-call limits, model, sampling settings and synthetic cases,
retained separately. No tuning or response repair during this comparison.

Second window completed: all 20 cases scored, 13 passed, 56 generation calls,
240.062 seconds, no infrastructure failure, idle verified at the end. See the
[v2 comparison review](../assessments/CONTINUITY_LAB_A3_V2_REVIEW.md) for audited
tool results and dependent failures. Both approved batches are consumed;
additional live inference requires a new bounded window.

Close transport and reap the foreground worker on failure; retain receipts and
partial journal without automatic rerun. No live-model mutation needs rollback.
If server idle cannot be verified after disconnect, report that uncertainty and
do not resume inference. The user may inspect retained state before any later
recovery. Dashboard integration, ordinary user data, a persistent experiment,
8K context and production deployment remain outside this approval.
