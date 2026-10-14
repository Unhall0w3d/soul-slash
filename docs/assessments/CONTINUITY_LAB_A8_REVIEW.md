# Continuity Lab A8 meaningful-passage comparison

Date: October 8, 2026 (America/New_York)
Status: **fixture and harness ready; one approved live attempt stopped during
calibration on admission-lock contention, before any generation**. No A8
behavioral result. Step 4 remains open; resident Qwen is unchanged and idle.

## Scope and implementation

The owner's "please proceed" accepted the meaningful-passage comparison proposed
after A7. The [A8 brief](../soul/CONTINUITY_LAB_A8_BRIEF.md) records that scope.
New files:

- `lib/soul_core/continuity_lab/qualification_cases_a8.rb`: seven fictional
  observation passages replace repeated-letter filler. Exact source IDs,
  768-character spans, requested offsets, case order, request text and marker
  positions remain unchanged. Short space padding aligns complete sentences.
- `scripts/verify-continuity-lab-comparison-a8.rb`: matched contracts, new source
  grounding, strict scoring, calibration margins and malformed sizing cases.
- `scripts/qualify-continuity-lab-qwen-a8.rb`: A7-derived harness with an explicit
  zero-generation calibration mode and a 64-token sizing margin requirement.

Expected prefixes and actual-condition scoring reuse A6 logic; the A8 wrapper
replaces the corpus digest with the correct new digest. Expected actions/results
remain in-memory sizing data, never inserted into live journals. No forced
next action or answer-producing controller was added.

All 23 A7 baseline code/grammar hashes remain unchanged. Live A8 baseline
settings, configurations, model/server hashes, props/template, protocol,
execution profile and time/call bounds exactly match A7. The changed experimental
variable is corpus style; it does not imply identical tokenization. Within each
pair, request/corpus/scoring contracts are identical except the pre-existing
3072 versus 2048 input budget. The four-case order stays counterbalanced.

## Deterministic checks and review

Pinned Ruby: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.

| Verifier under `scripts/` | Passing checks this turn |
| --- | ---: |
| `verify-continuity-lab-comparison-a8.rb` | 52 |
| `verify-continuity-lab-comparison-a6.rb` | 39 |
| `verify-continuity-lab-scoring-a4.rb` | 18 |
| `verify-continuity-lab-token-context-a5.rb` | 41 |

All **150 focused checks pass**, plus syntax for the three new Ruby files.
A7's 656 deterministic/isolation checks are retained evidence for unchanged
components, not claimed as freshly rerun A8 checks.

Luna's read-only review confirmed paired contracts and found an over-escaped
regex in the prose verifier. It was fixed and given an explicit repeated-letter
positive test. Review also proposed enforcing exactly one omitted group. That
would change A6/A7's actual contract, which requires group zero absent at the
boundary and can legitimately drop more than one oldest group. Instead, primary
strengthened sizing to reject empty, gapped, reordered or out-of-range retention
and require a contiguous suffix including the newest group. Tests permit valid
multi-group omission while rejecting those malformed selections. No scoring or
runtime packing semantics changed.

The separate CLI preflight again reported provider reachability failure and
warnings. It does not establish this desktop turn's authority or an app outage.
Exact host escalation was used; no broad privilege, service or network changes.

## Tokenizer-only calibration

Two non-generative sizing invocations ran, each bounded to 120 seconds:

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/qualify-continuity-lab-qwen-a8.rb --calibrate-only
```

Private retained roots:

- `Soul/runtime/qualification/continuity-lab-a8-sizing-20261008T202808Z/`
- `Soul/runtime/qualification/continuity-lab-a8-sizing-20261008T203044Z/`

The first candidate established the raw contrast, but re-read rollover was only
12 tokens above its boundary. Its original `valid=true` receipt is preserved;
it predates the stricter 64-token margin. Before generation, three descriptive
sentences in the re-read corpus were replaced with meaningful observational
measurements. This was the only corpus-sizing revision. The second candidate
passed all four margins and was frozen. No sampling/prompt/answer changes.

| Case | Selected tokens at expected points 0–4 | Margin |
| --- | --- | ---: |
| Four reads / visible | 785, 1217, 1650, 2096, 2511 | 561 |
| Re-read / rollover | 786, 1246, 1700, 1688, 1695 | 101 |
| Four reads / rollover | 787, 1223, 1660, 1673, 1655 | 481 |
| Re-read / visible | 785, 1243, 1695, 2142, 2601 | 471 |

Visible margin is remaining budget on the largest selected expected input;
rollover margin is full input above budget at the designated boundary. Actual
histories must still be measured independently. Random lineage identifiers vary
token counts, so the live harness recalibrates each fresh store before generation.

Both sizing invocations used zero generations, created four empty stores each,
and finished idle in approximately 16.75 seconds. Re-evaluating their second-pass
measurements through the final strengthened guard reproduced all four results.

## One live attempt: admission interruption

Executed once:

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/qualify-continuity-lab-qwen-a8.rb --approved-quiet-window
```

Evidence: `Soul/runtime/qualification/continuity-lab-a8-20261008T203732Z/`.
Stopped at 16:37:50 EDT after **18.345 seconds**, exit 1. Model hashing and
initial preflight passed. The first expected-path sizing trace passed with
counts 784, 1214, 1645, 2089, 2502. Acquiring admission for the next sizing case
raised:

```text
SoulCore::ContinuityLab::AdmissionDenied
model admission unavailable: SoulCore::ModelRuntimeLeaseStore::LockUnavailable
```

**Zero generation calls, zero workers started, zero scored cases, four unstarted
cases.** This is neither 0/4 behavioral failure nor evidence for/against the
meaningful-passage hypothesis. `calls.jsonl` is empty. New stores have zero
transactions, events and notes, so there is no unresolved model intent.

The source path is unambiguous: `ModelRuntimeLeaseStore#with_control_lock`
uses nonblocking exclusive `flock`, and `AdmissionGate#with_window` translates
lock failure to admission denial. The harness releases admission between sizing
cases, leaving an opportunity for another participant to take the shared lock.
`ModelRuntimeControlService#status` also acquires it; contention alone is not
proof of concurrent generation. The specific holder was not captured. Later
exact-path lock inventory found no holder, and the queried service journal had
no entries for that window; neither retrospectively identifies the cause.

The immediate final idle check failed while contention persisted. The existing
bounded read-only settle path succeeded after **0.214 seconds**. No restart,
lock deletion, lease pruning, automatic retry or second batch occurred.

## Integrity and final read-back

- All 19 historical A3–A7 stores validate. All 868 historical evidence files
  have the same aggregate content/path digest before and after A8:
  `e559c4cbbf3c05c21e6412ddc3ef83ce7939e28927934ea9c1bb5c249aacd06e`.
- All twelve new stores (eight sizing, four attempted-live) validate and are
  empty. All 81 new evidence paths are owner-private and non-symlinked.
- All 24 source/grammar hashes from the attempted-live baseline still match.
  Its case specifications exactly match the frozen second sizing candidate and
  current catalog. Later sizing-helper extraction did not change that corpus.
- Independent admission/observer read-back succeeded: same service PID 3058,
  build b9851, Qwen3-8B-Q4_K_M, 4K single idle slot, Core `amd-free`, selected
  `nvidia-fallback`, no retained lease or pending transition. No exact isolated
  worker argv remained. Pre-run GPU sample: 5,303/8,192 MiB and 0% utilization.

## Next decision

Preparation is complete; behavioral qualification is not. The one-attempt limit
in the approved A8 brief ends this window despite the zero-generation stop.
The debugging workflow identified the failing layer without inventing a holder
or weakening admission. No inference is running in the background.

Recommended next scope: a narrowly bounded readiness retry for **LockUnavailable
only, before the first generation**, retaining each collision and rechecking
all ordinary admission conditions on every attempt. Do not retry an in-flight
generation, unresolved intent, active/retained lease, failed identity check or
other admission error. Then perform one fresh comparison with this frozen corpus.
This would address transient pre-generation collisions without changing the
model or turning a failed live request into automatic regeneration. It is a
proposal, not implemented or exercised in this window. Dashboard, ordinary-memory,
merge/release and sustained-continuity acceptance remain open.
