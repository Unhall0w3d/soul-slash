# Continuity Lab A9-A12: admission, message format and remaining rollover decision

Date: October 8, 2026. Status: **visible-history path qualified on two clarified
tasks; sustained rollover qualification remains open**. No production, dashboard,
ordinary-memory, merge or release promotion.

## Authority and implementation

The owner requested continuing with adjustments until the intended working state.
[A9](../soul/CONTINUITY_LAB_A9_BRIEF.md) records iterative, bounded foreground
qualification rather than repeating an artificial one-attempt approval gate.
Every trial used new isolated stores; no interrupted historical intent was resumed.
The remaining context-policy decision is materially different from another trial.

- Admission now supports opt-in waiting for transient control-lock acquisition:
  at most five seconds / 21 attempts. Existing callers still refuse immediately.
  An entry flag prevents replay of lease checks, identity checks or caller work.
  Retained leases, integrity failures, occupied slots and post-entry exceptions
  are not retried. The lock still spans the worker lifetime, including reaping.
- [A10](../soul/CONTINUITY_LAB_A10_BRIEF.md) adds a host-only, fixed chronological
  assistant/tool message projection. Original selected envelopes and raw actions
  remain journaled. No generated summary, calculated progress, next action,
  answer injection or private context is introduced. JSON angle brackets are
  escaped to prevent template control-token interpretation without changing
  parsed values. Projection profile, rendered prompt and exact token IDs are
  retained in qualification receipts.
- [A11](../soul/CONTINUITY_LAB_A11_BRIEF.md) preserves v1 and adds v2: exact-value
  guidance plus original call_index placed after the source result. These are
  presentation changes; an attempt index is not a success receipt.
- [A12](../soul/CONTINUITY_LAB_A12_BRIEF.md) clarifies two visible-case requests:
  marker means the uppercase-letter/hyphen/digit identifier alone. It preserves
  corpus, exact action contract and strict scoring. This is a new request variant,
  not a retroactive pass for earlier ambiguous requests.

Legacy default formatting and configurations remain unchanged. The installed
Qwen model, grammar, sampler, 4K resident context, output/call limits, service,
GPU ownership and worker capabilities were not changed. All projections remain
opt-in through qualification harnesses.

## Live evidence

Private evidence roots are under `Soul/runtime/qualification/`.

| Trial | Root suffix | Calls | Strict result | Elapsed |
| --- | --- | ---: | --- | ---: |
| A9 | `a9-20261008T211033Z` | 22 | 0/4 | 169.784 s |
| A10 sizing | `a10-sizing-20261008T211611Z` | 0 | Contrast not established; stopped before generation | 17.283 s |
| A10 | `a10-20261008T211723Z` | 21 | 0/4 | 175.622 s |
| A11 | `a11-20261008T212112Z` | 21 | 0/4 | 170.085 s |
| A12 | `a12-20261008T212646Z` | 10 | **2/2, including intended visibility** | 91.033 s |

Prefix each root suffix above with `continuity-lab-`.
All live trials completed without infrastructure interruption and verified idle
at their end. No live contention happened in A9; bounded contention recovery is
demonstrated by deterministic and real-flock tests, not a manufactured live claim.

A9's first visible case stopped after three reads with literal reply "marker".
Other cases repeated reads. Meaningful text alone did not fix task adherence.

A10's initial guide lacked the legacy JSON shape examples and made the planned
reread rollover boundary too small. Its non-generative sizing failure is retained.
The six generic examples were restored before the next live trial; no task code
or answer was added. New calibration passed with margin.

A10/A11 performed the four requested reads in order in three cases, then replied
with labels/punctuation or surrounding text. The rollover reread case continued
reading. These remain strict failures; no scorer or response normalization hid
the errors. A11's three ordered sequences were not full qualification passes.

A12, with the clarified output specification, produced:

- Four reads: offsets `0,768,1536,2304`, then exact `TEAL-42`.
- Required reread: offsets `0,768,1536,0`, then exact `OPAL-19`.
- Five calls per case, all source/result contracts satisfied, full history
  visible at every planned decision, no extra read or repaired output.

These are two single-seed instruction-variant successes, not replicated
long-horizon reliability or a new general note-lifecycle qualification. Historical
note/restart qualification remains historical; it was not silently relabeled as
new-profile coverage.

## Why rollover is still open

Primary inspection and an independent Sol critique agree on an information gap.
In A11 reread-rollover, decision call 3 sees only successful pairs 1 and 2. After
the correct reread at index 3, decision call 4 sees only successful pairs 2 and 3.
It has no retained evidence that omitted attempts 0 and 1 succeeded. The current
request asks for four successful reads; attempt numbering cannot prove that.

This establishes lost evidence in the input, **not proof of the model's internal
reason for repeating**. More wording cannot restore missing success evidence.
The current minimal profile intentionally drops whole pairs. Its eligible
history excludes the current event and tool/audit records; optional notes were
not part of this strict four-read contract.

Recommended separate Soul profile: retain bounded verbatim action/result
receipts (identity, original index, success/failure and provenance), dropping
older bulky source text. Keep recent answer-bearing text exact. Preserve the
original minimal profile as a comparison condition. No inferred completion,
model-authored summary, forced next action or private-memory injection.

**Decision requested, not implemented:** this changes A1's whole-group context
policy and the experiment's available evidence. An asynchronous question was
presented to the owner. The authorized unaffected visible-history work is
complete; no background process is waiting for that answer.

## Deterministic / isolation verification

Pinned Ruby: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.
682 distinct checks passed across the focused suites; duplicate reruns are not
added to the count. All these commands were exercised in this work, not merely
copied from earlier reviews:

| `scripts/verify-continuity-lab-*.rb` suffix | Checks |
| --- | ---: |
| core-a0 / recovery-a0 | 21 / 149 |
| context-a1 / recovery-a1 | 30 / 94 |
| admission-a2 / isolation-a2 | 14 / 40 |
| qwen-a3 / scoring-a4 / a4 | 15 / 18 / 38 |
| token-context-a5 / comparison-a6 | 41 / 39 |
| stream-a7 / stream-isolation-a7 | 40 / 17 |
| comparison-a8 / admission-a9 | 52 / 39 |
| message-projection-a10 `--isolation` | 23 |
| comparison-a12 | 12 |

New admission checks include actual flock contention/release, exhausted wait,
stalled-clock attempt cap, default one attempt, no snapshot before acquisition,
no replay on provider/body lock exceptions, integrity/I/O/lease/busy refusal,
interrupts and callback failure. A reviewer initially expected 21 callbacks in
the advancing-clock test; primary rejected this finding because the post-sleep
deadline check terminates after 20 sleeps. The stalled-clock test separately
reaches the 21-attempt cap. No production change was made for that false finding.

Projection checks preserve Unicode, literal escapes, rejected results, original
indices and omitted prefixes; prove parsed-data equivalence and default-off
behavior; and bind exact prepared tokens to single-use generation. Both v1/v2
passed actual isolated-worker execution, journal reconstruction, worker reaping
and terminal resume without inference. Isolation tests use synthetic backends,
not the resident model.

## Integrity and read-back

- Independently reopened and validated **49** A3-A12 stores, without resuming any
  event. All **922** pre-A9 evidence files matched their captured SHA-256 values.
  Initial map digest: `ec7c6cdbb7023a96fdf7c50c6008c2708d26ebf3aba323fa0435ee861d89b9e6`.
- New A9-A12 evidence paths are owner-private and not symlinks. Latest A12
  baseline's **26** code hashes match current relevant implementation/harness.
- Final host check: unchanged PID 3058, Qwen3-8B-Q4_K_M on nvidia-fallback,
  amd-free core, zero active slots, no pending transition/retained lease; no
  isolated worker remains. GTX 1070: 5303/8192 MiB, 0% sampled utilization.
- No service restart, model load/switch, ordinary-memory write, package/network
  change, Git commit, merge or release. Dirty unrelated work is preserved.

Human acceptance and the receipt-retention decision remain distinct from all
the evidence above.
