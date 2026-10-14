# Continuity Lab A6 visible-history comparison

Date: October 8, 2026 (America/New_York)
Status: **comparison prepared and checked; live window interrupted/unscored**.
No dashboard, ordinary-memory, service/model change, merge or release.

## Scope and implementation

The owner's "please continue" accepted the controlled comparison proposed after
[A5](CONTINUITY_LAB_A5_REVIEW.md). The [A6 brief](../soul/CONTINUITY_LAB_A6_BRIEF.md)
records two matched pairs and one fresh bounded window. New files:

- `lib/soul_core/continuity_lab/qualification_cases_a6.rb`: two 768-character
  four-step read tasks, each with identical request/corpus/scoring contract across
  the 3072/2048 input-budget arms. Second pair reverses arm order.
- `scripts/qualify-continuity-lab-qwen-a6.rb`: fresh independent stores, mandatory
  tokenizer-only expected-path calibration, separate task score and observed
  condition, maximum four cases/24 generations/480 seconds.
- `scripts/verify-continuity-lab-comparison-a6.rb`: fixture/contract checks.

Runtime, broker, prompt guide, grammar, sampler and worker were not changed.
All 21 A5 baseline code/grammar hashes matched before the new window. No model
progress summary, receipt interface or forced next action was introduced.

Expected sizing traces are in-memory synthetic fixtures, never model evidence
or inserted into worker journals. Random lineage IDs differ between independent
stores; one unreplicated pair cannot establish general causal or reliability
claims. Expected responses are canonically serialized; actual model JSON may
have different token counts. Only actual per-call manifests establish visibility.

## Deterministic evidence

Pinned Ruby `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`:

| Command | Passed checks |
| --- | --- |
| `scripts/verify-continuity-lab-comparison-a6.rb` | 39 |
| `scripts/verify-continuity-lab-scoring-a4.rb` | 18 |
| `scripts/verify-continuity-lab-token-context-a5.rb` | 41 |

All **98 checks** pass; the three new Ruby files pass syntax. An initial filler
length error was corrected before inference. Luna independently checked paired
contracts and confirmed the 39 new checks. Review also identified the need to
require observed conditions for overall comparison success: the harness records
`qualified_comparison = passed && intended_condition_observed` and requires all
four for exit 0. This was fixed before the live window. Existing actual isolation
evidence is reused because its runtime/profile/worker paths remain unchanged.

The separate CLI preflight reported provider-reachability failure and several
warnings; it does not attest this app's permissions or establish an app outage.
Exact supported host escalation was used, not a broader privilege change.

## Tokenizer calibration and live attempt

Executed once:

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/qualify-continuity-lab-qwen-a6.rb --approved-quiet-window
```

Private Git-ignored evidence root:
`Soul/runtime/qualification/continuity-lab-a6-20261008T183918Z/`.

All four expected-path calibrations passed before generation. Selected token
counts for decision points 0 through 4:

| Task / arm | Counts |
| --- | --- |
| Four reads / visible | 785, 1088, 1492, 2090, 2684 |
| Re-read / rollover | 783, 1095, 1503, 1793, 1697 |
| Four reads / rollover | 784, 1085, 1487, 1782, 1972 |
| Re-read / visible | 784, 1098, 1508, 2112, 2426 |

Visible expected paths retain every prior result. Rollover expected paths omit
group 0 by the selected boundary. These are sizing results, not task passes.

The live batch ended at **14:40:24 EDT** after **66.306 seconds**, exit 1:
four generation requests started, three responses received, **one interrupted /
unscored case and three unstarted cases**. Zero completed/scored cases; not 0/4
behavioral failures. No second batch, retry, journal resume or tuning occurred.

First case, `four-reads-visible`:

| Call index | Actual input tokens | Retained groups | Returned result |
| --- | --- | --- | --- |
| 0 | 785 | none yet | successful read `[0,768)` |
| 1 | 1097 | 0 | successful read `[768,1536)` |
| 2 | 1510 | 0,1 | successful read `[1536,2304)` |
| 3 | 2117 | 0,1,2 | no complete response before timeout |

No context was omitted. The fourth call raised `BackendUnavailable` wrapping
`Timeout::Error`. Its committed model intent has no response. The store remains
pending with unresolved intent, not an accepted failed/complete terminal, and
must not be silently regenerated. The three other stores have no events.

## Timeout diagnosis and final read-back

Read-only service logs show task 8665 started at 14:39:54. Prompt ingestion
reached 2048 tokens at 14:39:58. Decode continued from 100 tokens at 14:40:03 to
548 at 14:40:24, at roughly 21–22 tokens/second. The server cancelled the task and
released its slot at 14:40:25. It was still producing output, not shown to be a
GPU crash or a dead service. The non-streaming client retained no partial body,
so the output's content/validity and reason for its length are unknown.

The 30-second HTTP ceiling can expire before the configured 768-output-token
allowance completes at this observed speed, especially after prompt ingestion.
That is a timing-contract limitation, not proof that permitting more time would
produce a correct answer. Merely raising the request timeout also has to account
for the existing 60-second whole-worker/event ceiling.

The immediate harness idle check was false while cancellation was settling;
that original receipt is preserved. A subsequent independent admission/observer
check confirmed zero active slots, no pending transition, same service PID 3058,
Core `amd-free`, profile `nvidia-fallback`. Service active/running; GTX 1070
allocation remained 5303/8192 MiB, with 0% utilization at read-back. No isolated
worker remained. There was no service restart or model switch.

All four stores reopen and validate. The interrupted store has 11 transactions,
one event, zero notes, head digest
`60c71536863cb90019a07c850f3f9d20d56309f07b43a73970d278f8de9c2dca`.
Primary matched all four committed selections to prepared prompt/token digests.
All 22 A6 baseline code/grammar hashes matched disk after the run. All 39 evidence
paths had no symlinks or group/other permissions; the root is Git-ignored.

## Conclusion and next decision

The comparison remains unqualified. This run demonstrates correct first-three
read order with full visible history, then an overlong generation before any
omission. It cannot establish which condition improves final-answer behavior.

Before another live attempt, specify a diagnostic timeout contract: retain
bounded partial output on interruption and reconcile per-request output/time
allowances with the whole-event deadline. Any streamed transport or changed
timeout/output allowance needs its own deterministic disconnect/cancellation
checks and explicit new experimental condition. Do not infer that a larger
timeout alone fixes model behavior or start a second batch automatically.

The approved window is finished. Step 4, dashboard and ordinary-memory activation
remain open/held. The planning and evidence-review workflows separate this
completed investigation from successful model qualification.
