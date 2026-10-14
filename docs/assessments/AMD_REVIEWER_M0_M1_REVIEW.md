# Optional AMD reviewer — M0 inventory / M1 detached fake workflow

2026-10-13. **M0 complete; M1 candidate-complete with deterministic evidence.**
No real reviewer or training model was launched. No review has been exposed to
Soul or LibreChat. M2+ inference/integration/training remain unexecuted.

Approved scope: [M0/M1 brief](../soul/AMD_REVIEWER_M0_M1_BRIEF.md), derived from
the operator's DOCX handoff, accepted review amendments, and explicit additional
revision/availability/visibility safeguards. This assessment is not a grant of
merge, release, unattended execution, GPU activation or memory promotion.

## M0 — current host observations

Read-only host checks were collected at 18:22–18:34 UTC. Initial sandbox queries
could not reach the user bus or NVIDIA driver; narrowly escalated read-only
checks succeeded. These initial failures were sandbox visibility limits, not
evidence of broken drivers. The Codex preflight separately reported restricted
CLI provider reachability and warnings; it does not attest to app-turn authority.

| Item | Observed state |
| --- | --- |
| NVIDIA primary | GTX 1070, driver 580.178.04, 8,192 MiB total; about 5,283 MiB used |
| Resident process | Same PID 1079343 throughout; active/running `llama-server.service`; sole NVIDIA compute client |
| Model and runtime | Qwen3-8B-Q4_K_M, 4,096 context, `soul-local-chat`, loopback 8082; b9851 CUDA sm61 binary |
| AMD | RX 6900 XT, PCI `0000:0a:00.0`, Vulkan0/RADV NAVI21, Mesa 26.2.2; about 13.18 GiB free at admission observation |
| Desktop | Hyprland and quickshell present; AMD admission observer passed its point-in-time ownership check |
| AMD services | `soul-model-gemma.service` and `soul-model-dev.service` installed but inactive; both use Ollama/Vulkan, not a new standalone reviewer |
| Selection vs default | Persisted selection `nvidia-fallback`; registry default remains `amd-gemma`. Neither was changed |
| RAM / swap / disk | About 36.3 GiB available RAM, 4.7 GiB occupied swap, 608 GiB free disk; two short interval samples had small swap-ins and no swap-outs |

The free-memory observation is not a reservation and does not qualify gaming
coexistence. Existing cooperative admission cannot prevent an unrelated game
from allocating AMD memory later. No GPU workload or full-release test occurred.

Existing A23 GGUF files and the pinned publisher manifest were inventoried:
Ministral 3 14B Q4_K_M (8.24 GB), Qwen30 Q4_K_M (18.56 GB), and Qwen35 UD-Q4_K_M
(22.13 GB). The larger two cannot be assumed fully resident on a 16 GB card.
Their bytes were not rehashed in M0; prior A23 hashes and current size/mtime
are separate evidence. Ollama manifests for Gemma4 12B, GPT-OSS20B and the local
chat alias were found; manifest presence is not model-load/training qualification.

The current Qwen8 model and NVIDIA binary were rehashed, matching the recorded
baseline: model `d98cdcbd03e17ce47681435b5150e34c1417f50b5c0019dd560e4882c5745785`,
binary `9b774d211090d3bff738fdb9b17f1ee7e3afa40774a0455f9f81399ff9d69e81`.
All 44 existing Continuity source files and seven inventoried user-unit files
retained their before/after hashes. No service restart, model switch, profile,
package, driver, firewall, startup, credential or ordinary-memory change occurred.

## M1 — implemented behavior

New code is in `lib/soul_core/reviewer/`, deliberately outside A22's fingerprinted
`continuity_lab/` tree. It reuses existing strict canonical JSON and fd-anchored
private-directory handling without altering those classes or journal schemas.

- Closed Ruby request/response schemas bind the exact source answer, event ID,
  ordered evidence packet, question, constraints and rubric. Each excerpt has a
  verified text hash; the full request and immutable completion have digests.
  References must exist in the packet. Hash consistency is not proof of truth.
- Duplicate ID with the same request is idempotent; changed content conflicts.
  Historical completion remains intact when explicit current revisions differ.
  Freshness is `current`, `stale`, or `unknown` when current revisions are absent.
  This is a comparison against caller-supplied revisions, not a live source watcher.
- `queued -> leased -> running -> completed/failed/canceled/indeterminate`, with
  queued cancellation and expiry. Late results require the exact active attempt
  and unexpired deadline. Explicit recovery never requeues unresolved work.
- Unavailable review leaves the request queued with the exact message
  `Reviewer unavailable. Request retained for later review.` The original
  `advisory` versus `independent_required` contract is not changed.
- Advisory disposition is `may_proceed_without_review`; required disposition is
  `pending_independent_validation`. Even a completed fake run retains that
  distinction: it performs no semantic assessment and establishes no validation.
- Runtime provenance is supervisor-generated and binds contract, store and fake
  runner code. Generated response fields cannot override it. This is fake-provider
  provenance, not attestation of a real GPU model or isolation from a malicious
  process running as the same OS user.
- Owner-private manifest, lock and hash-chained atomic records survive reopen.
  Uncommitted stages remain inspectable and count against quotas. No file is
  automatically deleted. Limits: 128 retained requests, 2,048 transactions,
  16 MiB store, 64 KiB request, 32 KiB response, one-day request lifetime and
  at most 60 seconds per fake attempt lease. Exhaustion fails closed; historical
  records are not automatically pruned. Hash chaining has no external anchor and
  cannot establish adversarial same-user tamper resistance or detect all tail loss.
- The foreground CLI accepts no runtime command/provider injection. No daemon,
  listener, GPU lease, background consumer, automatic retry or model call exists.

## Recorded is not available, encountered or accepted

Every M1 record says `visibility: detached_not_available_to_soul` and
`acceptance: not_evaluated`. There is no delivery endpoint or note writer.

The future M4 contract must record separately:

1. **Recorded:** an artifact was committed.
2. **Available:** the artifact was offered through an authorized retrieval path.
3. **Encountered:** the exact revision was included in an actual model input.
4. **Considered:** an attributed model response reports engaging with it; not
   independent proof of comprehension or private reasoning.
5. **Accepted/rejected:** an explicit attributed disposition; neither mere
   incorporation in text nor a disposition alone proves durable policy adoption.

No per-record human acknowledgment is needed merely to make a future review
available. Action authorization, protected-memory promotion and training labels
remain distinct. LoRA trials are not implemented here; later experiments must
separate adapter-active, adapter-removed-with-historical-consequences and clean
baseline state, including journal/workspace and any other writable state.

## Validation and repaired findings

Pinned interpreter: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.

| Command (under `scripts/`) | Result |
| --- | --- |
| `verify-soul-reviewer-m1.rb` | 23/23 grouped contract/workflow checks |
| `verify-soul-reviewer-recovery-m1.rb` | 51 grouped recovery/CLI/provenance checks |
| `verify-continuity-lab-core-a0.rb` | 21/21 unchanged-boundary checks |
| `verify-continuity-lab-recovery-a0.rb` | 149 unchanged-boundary checks |
| `verify-continuity-lab-chat-gateway-a22.rb` | 25/25 unchanged-boundary checks |
| Ruby `-c` for three new classes, CLI and two verifiers | Six syntax checks pass |

**269 grouped deterministic checks pass.** These are synthetic workflow and
storage tests, not model-quality, live GPU cancellation, general security or
operator usability evidence. Changed-path resolution required targeted behavior
checks; all applicable commands above completed. No local LLM evaluation is
appropriate for deciding these persistence/authority properties.

Fault coverage includes before-write, after-stage, after-rename and after-commit
cuts; actual SIGKILL of an owned synthetic child; cross-process lock contention;
partial completion recovery; cancellation/attempt/deadline fencing; explicit
expiry/failure; hash corruption; unsafe hardlink/symlink/mode; existing-root
refusal; request/count/byte bounds; duplicate JSON keys; and CLI reopen/freshness.

A focused Sol read-only review identified a real signal-cleanup defect: a signal
just after completion could be replaced by a terminal-cancellation conflict.
Primary reproduced it with a failing after-rename test, fixed preservation of
the original interruption, and passed after-rename/after-commit regressions.
Runtime fingerprinting initially omitted the fake runner; it now covers all
three reviewer implementation files. Two test inputs with independent rejection
causes were corrected to make fencing assertions discriminating. Initial
fixture-only timestamp/entry-shape mismatches were also corrected and disclosed.

## Retained evidence and reproduction

Evidence root:
`Soul/runtime/qualification/amd-reviewer-m0-m1-20261013T1821/`.

- `inventory.json`, `inventory-supplement.json`: bounded host observations,
  service/profile distinctions, model metadata, source and configuration hashes.
- `host-readback.json`: unchanged baseline PID/model/runtime arguments, sole
  NVIDIA compute client, inactive AMD services and desktop process presence.
- `fake-demo-and-preservation.json`: synthetic advisory/required/unavailable
  results, completed/stale artifact and source/config preservation read-back.
- `fake-review-demo/`: actual replayable fake store. One advisory request is
  completed; one required request remains queued. This is inert data, not a job
  left running. It may expire on a later explicit recovery invocation.

CLI examples (repository root; substitute the pinned Ruby as needed):

```sh
ruby scripts/soul-reviewer status /absolute/private-parent/reviews
ruby scripts/soul-reviewer status /absolute/private-parent/reviews REVIEW_ID
ruby scripts/soul-reviewer status /absolute/private-parent/reviews REVIEW_ID sha256:CURRENT_ANSWER_HASH sha256:CURRENT_EVIDENCE_HASH
ruby scripts/soul-reviewer cancel /absolute/private-parent/reviews REVIEW_ID
ruby scripts/soul-reviewer recover /absolute/private-parent/reviews
```

For a new synthetic fixture: prepare a `0700` parent, run `init ROOT`, submit
the closed request JSON on stdin to `enqueue ROOT`, then `run-fake ROOT ID`
or `run-fake ROOT ID --unavailable`. The retained demo report contains a complete
request example; generate fresh epoch timestamps rather than reusing an expired
one. Root/ancestor symlinks and existing roots are refused. Store files are
`0600`; root is `0700`. Initialization parents and internal leaves must meet the
existing Directory contract. `status` without an ID gives a content-minimized
index; with an ID it returns the packet/artifact. Keep private packets local.

Exit 0 means the bounded CLI operation returned, including a documented
unavailable result; inspect JSON status/disposition. Exit 2 is failure; 130 is
interruption. An interruption may follow a durable commit: inspect the store
before any retry. Only exact enqueue retries are idempotent; a completed fake
run cannot be run a second time under the same ID. Clock rollback blocks new
mutation. Store manifest pins the fake implementation; future code upgrades
need an explicit compatibility/migration decision, not silent replay under a
different runner. Preserve the evidence and implementation version together.

## Next bounded gate

M2 is a separately approved real-AMD inference pilot, not authorized by M1
completion. Inventory existing usable binaries first; preserve CUDA/Qwen and
reuse the `amd-vulkan-generation` admission/lease group. Prefer a fitting cached
asset for infrastructure qualification before authorizing further downloads.
Measure load/first-token/throughput/release, bounded cancellation, headroom,
thermal/paging and desktop impact. Do not infer reviewer accuracy from A23.
M3 adds self-review and evidence-first controls, false corrections and new
held-out cases. M4 alone adds bounded attributed visibility into Soul; none of
M2–M6 is required just to retain the existing LibreChat connection candidate.

Changed paths: three new reviewer classes, `scripts/soul-reviewer`, two new
verifiers, this assessment, the brief, and additive entries in
`docs/soul/HUMAN_REVIEW_GATE.md` / `skills/_template/REVIEW.md`. Existing dirty
work was preserved. No commit/push, deletion, promotion, active worker or
scheduled continuation was created. M0 artifacts are local operational data;
fake fixtures contain no real conversation. Ordinary memory keys used: none.
Risk: bounded local persistence candidate, with no external execution surface.
