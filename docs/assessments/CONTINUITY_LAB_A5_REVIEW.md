# Continuity Lab A5 actual-token packing and focused qualification

Date: October 8, 2026 (America/New_York)
Status: **packing repair implemented and exercised live; behavioral qualification
requires follow-up**. Dashboard / ordinary-memory / merge / release remain held.

## Authorized scope and implementation

The owner approved proceeding after the [A4 v3.1 review](CONTINUITY_LAB_A4_V3_1_REVIEW.md).
The [A5 brief](../soul/CONTINUITY_LAB_A5_BRIEF.md) specifies implementation and
one fresh nine-case synthetic window. No old interrupted event was resumed.

- New opt-in `qwen_tokenized_v1` configuration, protocol
  `qwen_envelope_v4_token_preparation`. Legacy profiles and journals stay unchanged.
- Host preparation measures the complete rendered prompt with the installed
  formatter/tokenizer, removing only whole oldest result groups until it fits.
  Instructions, current request and newest result cannot be dropped.
- The exact selected input, preparation, count/digests and omission manifest are
  journaled before generation. Generation consumes the host's cached prepared
  token array once; altered, stale or consumed preparations are refused.
- Replay reconstructs eligible selection and validates bindings without model
  calls. Recorded token counts remain trusted-host measurement evidence, not
  independent retokenization or cryptographic host attestation.
- Essential overflow commits a grounded failed terminal. Token overflow has a
  `context_rejected` record; interrupted committed rejection resumes only to its
  failure terminal. Unresolved model intent still blocks regeneration.

The existing 12,288-byte broker input cap precedes token measurement. It may
conservatively omit compressible input that could fit the token budget; manifests
distinguish `input_byte_limit` from `actual_input_budget`. This does not promise
maximal context utilization. Normal actual input ceiling remains 3,072; the
rollover fixture uses 2,048. Resident context remains 4,096 with output reserve
768 and margin 256. Model, prompt instructions, grammar and sampler are unchanged.
No action repair, forced next step or generated progress summary was introduced.

Primary owns runtime/persistence changes and live execution. Luna mapped tests
and independently audited completed note-chain receipts. Sol identified the
missing journal terminal for essential overflow; primary added rejection/replay
guards and fault tests before live use. Scoped follow-up static review found no
remaining overflow-path defect; primary executed all checks below.

## Verification before live generation

Pinned Ruby: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.

| Verifier suffix (`scripts/verify-continuity-lab-*.rb`) | Passed |
| --- | --- |
| `core-a0` | 21 |
| `recovery-a0` | 149 |
| `context-a1` | 30 |
| `recovery-a1` | 94 |
| `admission-a2` | 14 |
| `isolation-a2` | 40 actual isolated-worker checks, synthetic transport |
| `qwen-a3` | 15 |
| `scoring-a4` | 18 |
| `a4` | 38 |
| `token-context-a5` | 41 |

All **560 checks** passed; 32 Ruby files passed syntax checks. Initial new test
runs exposed an expected-exception mismatch and fixture variable scope issue;
those test defects were corrected and affected suites passed before live use.
All eight historical A3/A4 stores reopened with unchanged head digests, including
the two interrupted A4 stores; no historical event was resumed.

A bounded formatter/tokenizer-only check of the retained rejected A4 envelope
measured **3,774 → 3,427 → 2,946 tokens**, keeping groups `[2,3,4]` after removing
the oldest two. It made **zero generation calls**. This verified the original
sizing failure before the live batch.

The separate restricted CLI readiness probe reported provider/state-path failures
and warnings; it does not attest this app's permissions or establish an app
outage. Exact host checks used supported escalation; no unrelated repair.

## One live batch: 7 passed, 2 behavioral failures

Executed once:

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/qualify-continuity-lab-qwen-a5.rb --approved-quiet-window
```

Private Git-ignored root:
`Soul/runtime/qualification/continuity-lab-a5-20261008T181332Z/`.

Finished **14:16:01 EDT**, **148.497 seconds**, **25 generations**, exit 1 because
two scored cases failed. All nine cases were attempted/scored; no skips, unscored
events, unstarted cases or infrastructure exception. The seven-case chain passed:
exact reply, create/read/correct/read/tombstone/search. Nine distinct workers.

### Case 08: four reads, then answer

Expected offsets: `0,1024,2048,3072`, then `TEAL-42`.
Actual offsets: **`0,1024,2048,3072,0,1024`**. All six reads succeeded, but there
was no final reply. Event ended `failed/model_call_budget`.

Before generation five the full prompt measured 3,084 tokens. Packing omitted
group 0, yielding 2,733 with `[1,2,3]`; Qwen restarted at offset 0. Before
generation six, counts were 3,436 → 3,085 → 2,600, retaining `[2,3,4]`; Qwen read
1024. The fourth result had already returned the final marker.

### Case 09: re-read after omission, then answer

Expected offsets: `0,1024,2048,0`, then `OPAL-19`.
Actual offsets: **`0,1024,2048,0,1024,2048`**. All six reads succeeded, but there
was no final reply. Event ended `failed/model_call_budget`.

Before generation four, the journal manifest omitted group 0 and retained
`[1,2]` at 2,013 actual tokens. Qwen successfully re-read offset 0 with the same
corpus source/revision/digest/span. This demonstrates actual omitted-source
re-reading, **not a full case pass**. Later contexts retained `[2,3]` and `[3,4]`;
the model continued cycling.

The association between omissions and restarted steps supports a progress-loss
explanation, not a controlled causal conclusion. V3.1 also repeated a read before
any omission. The unchanged exact-sequence scorer does not excuse additional
successful tools; these probes do not test free-form notebook/history strategies.
Broader optional-memory usefulness remains a separate experiment.

## Final evidence and read-back

- Every one of 25 generations fit its actual selected budget; inputs ranged
  **720–2,733 tokens**, with server counts matching and no truncation. Total
  output **1,247 tokens**. No malformed actions.
- Primary matched every journal selection to host preparation, generation,
  prompt digest and exact token-array digest. Baseline source hashes, sampler
  and grammar match disk. No implementation changed during/after the run.
- 35 GPU samples all showed **5,303 / 8,192 MiB**; not a continuous peak benchmark.
- All 114 evidence paths have no symlinks or group/other permission bits; root
  is Git-ignored. No upload, Git addition, commit, deletion or promotion.
- End-of-run and independent admission checks showed zero active slots and no
  pending transition. `llama-server.service` remained active/running, PID **3058**.
  No isolated worker remained; no service/model/Core switch.

All stores validate with terminal events only:

| Store | Transactions / events / notes | Head digest |
| --- | --- | --- |
| chain | 46 / 7 / 1 | `9d77d8b5ca1f175eb27e00c71a95e7a79506eef715dca76fdbe44a3536363ba9` |
| independent | 20 / 1 / 0 | `bc6be35bc0099fe1c58699cf533ea2f01bb13dbd28eaebbee3563f26a187e585` |
| rollover | 20 / 1 / 0 | `eb1ac73d3a981eb75430c01ea2b8c7659c96163ddb3699a1713e9e5a8b6afac5` |

## Remaining decision and next proposal

The actual-token repair is implemented and exercised live. Step 4 overall is
**not accepted**: terminal adherence and sustained continuity remain unqualified.
The authorized batch is finished; no automatic retry or tuning.

Next, separate basic sequence completion from loss of prior action evidence:
compare smaller reads that keep all results visible against the current rollover
condition. If compact completed-action receipts are then added to model-visible
context, make that a new explicit interface/experimental condition, not a hidden
summary or retroactive fix. Keep deterministic execution history distinct from
optional model-authored notes. Do not force a next action, enlarge GPU/context
limits, or weaken scoring to manufacture a pass.

Dashboard integration and ordinary Soul memory remain unchanged and held.
