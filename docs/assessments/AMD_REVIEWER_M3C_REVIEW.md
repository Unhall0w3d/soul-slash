# AMD reviewer M3C — protocol comparison

2026-10-13. Scope: the approved three-arm reviewer improvement experiment in
[the M3C brief](../soul/AMD_REVIEWER_M3C_BRIEF.md). Production M1 and Continuity,
prior experiments, model defaults and LACT/hardware configuration are unchanged.

## Current status

Completed one approved foreground window:90 generations plus8 skipped revisions,
accounting for all98 planned slots across14 cases. The gate returned success and
all cleanup/preservation checks passed. Neither experimental arm meets the frozen
usefulness criterion. No production promotion, protocol retuning or quality rerun.

Evidence directory:
`Soul/runtime/qualification/amd-reviewer-m3c-20261013T224705Z-20261013-2158926-59omij/`.
`protocol.json` binds fixtures, source answers, implementation/brief, model/runtime
hashes and settings; `scores.json`, `summary.json`, per-request/response/validation
receipts, raw AMD streams, resource samples and preservation receipts are retained.
Generated reviews remain detached and unavailable to ordinary Soul memory.

The preceding admission refusal identified Opera PID2140081 at538.67MiB,
above the unchanged512MiB foreign-allocation guard. After the operator's go-ahead,
fresh admission passed with13.72GiB free. No application was stopped by the agent.
CLI preflight at22:46:45UTC reported provider reachability failure inside its
restricted sandbox; this is not app or local-model failure or expanded authority.

## Implementation and evidence

- `scripts/compare-amd-reviewer-m3c.rb`: fixed Qwen3.5 candidate, independent
  control/current/findings-first/claim-checks branches, rotated arm order,
  98-call ceiling, inherited bounded M3B lifecycle and immutable source/evidence
  bindings. Parseable invalid reviews retain raw output and skip only their
  own revision. Malformed/duplicate JSON and runtime failures stop the window.
- `scripts/support/amd_reviewer_protocol_m3c.rb`: field-level judgments, exact
  source-value and quote binding, complete unique coverage, deterministic
  aggregation and separate required-unit findings. Exact quotation does not
  prove entailment; valid structure is not acceptance or authority.
- Fourteen fresh synthetic fixtures, three per semantic verdict plus two
  format-only cases. Explicitly authored sources, not sampled Qwen answers.
  Mixed cases ask about actual values rather than falsely asserting an entry
  exists in a blank record. Public task projection excludes all oracle labels.

Pinned Ruby4.0.7 syntax passed for all five new Ruby files. Checks:

| Suite | Passing grouped checks |
| --- | ---: |
| Fresh M3C fixtures | 9/9 |
| M3C protocol/runner | 12/12 |
| Inherited M2 | 32/32 |
| Inherited M3 | 18/18 |
| Inherited M3B | 18/18 |
| Total | 89/89 |

The runner verifier includes a fake98-call window (42AMD/56NVIDIA calls), arm
rotation, independent revisions, invalid-review skip accounting, complete claim
coverage, source/citation tamper rejection and all1–3-field aggregate combinations.
Fake lifecycle results do not establish a live load or cleanup. Required-check
routing selects Ruby syntax and targeted behavior; both are satisfied.

Focused Sol read-only review identified failure-contract and metric ambiguities
before any inference. Resolved by distinguishing parse failure from parseable
invalid shape, recording supported-findings as not applicable for the claim arm,
separating unique correction from preservation wins, and counting skipped/invalid
revisions as losses whenever the control was correct. The ordering arm now moves
only verdict behind the unchanged relative order of omissions and findings.

## Remaining step and interpretation

The full experiment is complete; no continuing job remains. The next decision
is whether to narrow the proposed reviewer to unendorsed critique, retaining
deterministic integrity/format checks without claiming factual validation. The
present evidence does not warrant adding a claim-level review dependency to
LibreChat or promoting either new protocol. Any further prompt/schema/model
experiment needs a separately frozen comparison, not a rerun of these cases.

## Live quality results

| Arm | Correct semantic verdicts /12 | Strict final answers /14 | Invalid reviews | Unique corrections beyond control |
| --- | ---: | ---: | ---: | ---: |
| No-review reconsideration | n/a | 12 | n/a | n/a |
| Current | 6 | 12 | 0 | 0 |
| Findings before verdict | 6 | 11 | 0 | 0 |
| Claim-level checks | 3 | 4 | 8 | 0 |

Denominators include invalid/skipped reviews. Claim-checks completed only6
revisions;8 were skipped, not counted as correct or silently replaced. All90
issued calls produced complete parseable responses. Current and findings-first
each return the correct verdict on3 supported and3 contradicted cases, but label
all3 insufficient-evidence and all3 mixed cases `contradicted`. Neither spoils
the3 correct sources. Findings-first loses one control-correct case by returning
`sealed, not open` instead of the required exact `sealed`. All arms fail both
unit-format cases. Original strict answers were3/14; gains from reconsideration
alone are not gains attributable to review.

Observed raw key orders match the intervention in all14 cases per arm:
current=`review_id,verdict,omissions,findings`;
findings-first=`review_id,omissions,findings,verdict`. Verdict-last is actually
delivered, but gives no observed calibration benefit. This is output ordering,
not evidence about a hidden internal reasoning sequence.

Primary assessment plus Sol's read-only review of all14 cases found:

- Cases1–3: all arms preserve supported answers, including an explicit unknown
  replacement date. Accepted claim quotations are exact and contextually relevant.
- Cases4–6: legacy arms identify genuine explicit contradictions. Claim-level
  raw reasoning also identifies the contradictions, but omits mandatory citations
  and is rejected. Raw semantic correctness is not accepted-review completion.
- Cases7–9: missing pH, ballot count and facilitator identity are not proof the
  asserted real-world values are false. All legacy verdicts misclassify them,
  commonly with high confidence. Claim-level case8 passes citation integrity with
  the exact quote `Its seal log does not include a ballot count.` but still labels
  47 contradicted. This directly demonstrates that a real quotation does not
  establish entailment. Cases7/9 fail citations before an accepted verdict.
- Cases10–12: each contains one explicit contradiction and one unsupported
  field. Legacy arms flatten these to contradicted even where their rationales
  describe an unsupported field. Claim-level10 misclassifies both raw fields;
  raw11/12 statuses distinguish the two categories but lack required citations.
  Case11 also replaces the source service_date with `unknown` rather than copying
  `2026-08-14`: a second source-binding defect masked by the first citation error.
- Cases13–14: factual numbers are supported. Claim-checks correctly emits separate
  deterministic missing-unit findings and passes them, plus the public format
  rules, to Qwen. The revisions are still `4.25` and `16L`, not `4.25 kg` and
  `16 L`. These are downstream format failures under a string-only answer schema,
  not false numerical claims or demonstrated native-template failures.

All8 invalid reviews report `positive judgment lacks citation`. Exact matching,
complete coverage and source binding are useful integrity gates, but neither
their presence nor a successful aggregate verdict makes the model a trustworthy
semantic validator. The stricter arm loses8 control-correct answers through its
explicit skips. It is not acceptable to hide those losses by reporting only its
accepted subset. Supported-nonempty-findings is n/a for the claim schema, whose
claims are not equivalent to the legacy error-findings list.

## Runtime, cost and closeout

Qwen3.5-9B Q4_K_M loaded all34/34 layers on the reviewed AMD Vulkan device in
2.80s, with thinking disabled and the pinned sampler attested. NVIDIA's resident
Qwen3-8B remained PID1079343, same configuration and runtime. No adapter was used.

| Calls | Count | Mean response seconds | Median seconds | Input tokens | Output tokens |
| --- | ---: | ---: | ---: | ---: | ---: |
| AMD current | 14 | 3.910 | 4.114 | 9,372 | 2,150 |
| AMD findings-first | 14 | 3.896 | 3.946 | 9,400 | 2,164 |
| AMD claim-checks | 14 | 4.234 | 4.275 | 9,742 | 2,254 |
| NVIDIA controls + revisions | 48 | 1.451 | 1.430 | 14,543 | 802 |

Response timings exclude startup, model hashing, template/tokenizer calls and
the minimum3s cooldown before each AMD request (126.28s total). Different review
payload lengths are part of the intervention. This is a small seeded pilot, not
a representative workload or model-wide benchmark.

740 retained resource samples: peak74C edge,80C junction,66C memory; whole-device
VRAM peak7.54GiB; minimum available system RAM35.05GiB. System-wide swap-out
delta12,321 pages (48.13MiB), below the256MiB bound; not attributed solely to the
test. Approved abort limits90/100/90C and0.5s sampling remained unchanged.

`preservation.json`: source/config/brief hashes unchanged; inference-runtime
hashes unchanged; applied clocks/voltage/power/thermal settings unchanged;
own lease gone; no unsettled Qwen request; pilot endpoint closed. Owned AMD PID
2159564 is confirmed absent. Post-run Qwen is healthy/idle, Gemma/Dev services
inactive,8096 closed, and fresh AMD admission passes with13.89GiB free. No
hardware tuning, service/default changes, memory ingestion or release occurred.
