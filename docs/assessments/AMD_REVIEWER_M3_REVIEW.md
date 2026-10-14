# Optional AMD reviewer — M3 quality comparison

2026-10-13. **Bounded comparison complete; direct AMD review shows a small useful
effect, but reviewer correctness is not qualified for authoritative validation.**
No production review delivery, memory promotion, service/default change, LoRA,
LibreChat connection, merge or release occurred.

## Evidence and scope

- [Approved scope and frozen protocol](../soul/AMD_REVIEWER_M3_BRIEF.md).
- Successful lower-load window:
  `/home/bhones/Projects/soul/Soul/runtime/qualification/amd-reviewer-m3-20261013T201325Z-20261013-1965115-u4kowy`.
  `protocol.json`, 100 request/response pairs, 50 revision-bound review records,
  ten case-score records, `summary.json`, resource samples, runtime identity,
  release and preservation receipts are retained privately. Local API key files
  are credentials, not shareable report content.
- Original thermal-aborted attempt:
  `/home/bhones/Projects/soul/Soul/runtime/qualification/amd-reviewer-m3-20261013T200822Z-20261013-1959479-pn1jun`.
  Six completed responses and a partial seventh generation, zero complete cases.
  Original runner and brief copies match their preflight hashes. Do not pool
  this attempt into successful-run scores.

Ten synthetic cases were authored before inference and independently checked.
Each natural Qwen answer branches into fresh-context Qwen self-review, direct
AMD review, and AMD evidence-first review (independent derivation before seeing
the source). Each review is followed by a Qwen revision from the same original;
branches do not consume one another. Twenty additional authored-seed reviews
are calibration controls, not naturally occurring primary errors. All data is
fictional, detached and unavailable to ordinary Soul memory or conversations.

## Paired answer outcomes

Exact scoring requires all requested fields and units. No fuzzy rescoring was
applied. Ten cases contain fifteen scored fields.

| Path | Whole answers correct | Fields correct | Corrected wrong answers | Spoiled correct answers | Net corrections |
| --- | ---: | ---: | ---: | ---: | ---: |
| Qwen original | 6/10 | 9/15 | — | — | — |
| Qwen self-review then revision | 7/10 | 11/15 | 1 | 0 | +1 |
| Direct AMD review then Qwen revision | 8/10 | 13/15 | 2 | 0 | +2 |
| AMD evidence-first review then Qwen revision | 7/10 | 11/15 | 1 | 0 | +1 |

Direct AMD is better on one paired case than either alternative, worse on none,
and tied on the other nine. Self and evidence-first tie on all ten. These are
descriptive paired counts, not significance or general-reliability estimates.

- **Case 01, superseded policy:** Qwen initially uses revision 4 / 18 months
  instead of revision 5 / 24 months. Both AMD reviews identify the contradiction
  using `policy-r5`. Self-review incorrectly calls the original supported, yet
  its subsequent revision fixes the answer. The self path's net correction
  therefore cannot be credited to accurate review criticism.
- **Case 05, filtered chronological selection:** Qwen picks invalid R-21 rather
  than eligible R-44. Direct AMD review identifies the invalid status and Qwen
  fixes both ID and date. Self-review says supported and retains the error.
  Evidence-first correctly criticizes it but the revision retains the error;
  its independent derivation also invents nonexistent R-45 / unknown date.
  More model calls did not improve this case.
- **Cases 03 and 06 are unit-format misses:** all original/revised Qwen answers
  give the correct numbers (`17.5` and `14`) but omit required `kg` and `L`.
  Keep these as exact-contract failures, not arithmetic mistakes. Reviews do
  not surface the missing units. Independent AMD derivations include the units
  but this does not propagate to the final revisions.
- The six originally correct cases remain correct in every branch. No spurious
  criticism was observed on their natural answers or the five supported seeds.

Thus the four strict original failures are two factual errors and two formatting
errors. Direct AMD fixes both factual errors; no path fixes the unit omissions.

## Reviewer calibration is still deficient

| Authored seed class | Qwen correct verdict | AMD correct verdict |
| --- | ---: | ---: |
| Supported | 5/5 | 5/5 |
| Positively contradicted | 1/3 | 3/3 |
| Insufficient evidence | 0/2 | 0/2 |
| Total | 6/10 | 8/10 |

The unsupported seeds assert a 12 kg harvest and an 8-hour runtime where no
quantity/duration was recorded. Qwen calls both supported. AMD notices the
unsupported assertions but calls both **contradicted**, despite explicit common
verdict definitions. Its harvest rationale treats missing records as direct
contradiction; its runtime rationale says no duration is established while the
verdict still says contradicted. This repeats M2's calibration problem.

Schema-valid output and valid evidence IDs do not make the criticism correct.
A review being recorded or displayed does not establish acceptance, comprehension,
durable adoption, or independent validation of a task.

## Timing and actual configurations

The complete inference window used 60 Qwen calls and 40 AMD calls. Measured
generation/stream/validation time totals 274.01 s; explicit AMD cooldown adds
120.27 s. Startup was 2.75 s. There were 200 two-second resource samples. Model
hashing/preflight, template rendering/tokenization and ordinary receipt overhead
are outside the generation timings below; these are not full user-visible SLAs.

| Path | Generation calls per case | Mean measured added time per case |
| --- | ---: | ---: |
| Original answer | 1 Qwen | 1.77 s (baseline) |
| Self-review plus revision | 2 Qwen | +5.72 s |
| Direct AMD review plus revision | 1 AMD + 1 Qwen | +7.92 s, including 3.01 s cooldown |
| Evidence-first plus review plus revision | 2 AMD + 1 Qwen | +11.95 s, including 6.01 s cooldown |

Seed audits are excluded from these path totals. All-call AMD median generation
time is 2.44 s (mean 3.16, max 8.06), median first token 1.63 s. Qwen median is
1.90 s (mean 2.46, max 12.19), median first token 1.31 s. Token totals are AMD
25,216 input / 2,900 output; Qwen 25,970 input / 1,611 output. These local calls
are not a measure of Codex subscription consumption or GPU energy cost.

Both use model-native templates, 4096 context, <=3072 input, 768 output, seed4242,
temperature .05, top-p1/top-k0/min-p0, repeat penalty1 and prompt cache disabled;
Qwen thinking is explicitly disabled. **A remaining default was discovered in
the returned settings:** Qwen inherits presence penalty .5, AMD inherits 0.
These receipts are not a fully sampler-matched model ablation. The paired
branches still use the same Qwen configuration, but comparisons of reviewer
models concern the actual runtime configurations, not weights alone. Pin all
relevant penalties and verify returned settings before any fresh ablation; do
not retroactively alter these scores or rerun until a preferred result appears.

All inputs fit; no successful response was truncated or accepted partially.
The stricter native stream parser was exercised on actual AMD SSE and raw AMD
wire data is retained as base64 in receipts.

## Thermal adjustment and final host state

First attempt: sample edge 84 C / junction 99 C exceeded the conservative 80/95
cutoffs and triggered teardown. The preceding sample was 45/58 C. This proves a
resource-bound stop, not physical damage or a diagnosed cooling fault. Sampling
every two seconds cannot guarantee temperatures never briefly cross a threshold.

The explicitly initiated v2 attempt changes AMD batch/microbatch from 512/128
to 128/32 and adds a minimum three-second gap, waiting for edge<=55/junction<=70
within thirty seconds. Abort limits were not raised. No power, clock, fan, LACT,
driver or production service changes were made. Same cases, prompts and scoring;
case one's earlier outputs had been observed, so this is a declared repeat, not
ten entirely unseen cases. No automatic retry loop exists.

Successful run observations:

- Cached publisher-pinned Ministral 3 14B Q4_K_M, installed Ollama-bundled
  llama.cpp/Vulkan runtime; 41/41 layers attested on AMD. Owned PID 1965834.
- Peak sampled edge/junction/memory temperatures **77/88/62 C**.
- Peak whole-device VRAM 10.89 GiB; minimum whole-host available RAM 32.13 GiB.
  Whole-host swap-in +144 pages; swap-out +0. Do not attribute every global
  counter or desktop allocation exclusively to this job.
- Sixty-five tracked source/config files and runtime binary/library hashes
  matched at teardown. M1, Continuity sources, selected Core/profile and unit
  files unchanged. Qwen PID remains **1079343**, active/running.
- Owned AMD PID absent, 8096 closed, private workload lease gone, no unsettled
  Qwen request, AMD VRAM returned within initial+256 MiB tolerance. Independent
  read-back confirms Qwen health `ok`, one idle 4096-token slot, and existing
  Gemma/Dev services still inactive. Qwen allocation changed from 5278 to
  5296 MiB after inference; PID/config preservation is not byte-identical GPU
  allocation or an untouched inference cache.
- One post-run admission probe reported a foreign AMD allocation. Later targeted
  PID inspection confirms the reviewer is gone; only Hyprland was above 512 MiB
  in that later scan. This does not identify the earlier transient owner or
  establish that all AMD workloads are idle. No desktop application was evicted
  and no gate weakened. Future work must perform fresh admission.

## Implementation and deterministic evidence

New files: `scripts/compare-amd-reviewer-m3.rb`,
`scripts/support/amd_reviewer_cases_m3.rb`,
`scripts/verify-amd-reviewer-m3.rb`,
`scripts/verify-amd-reviewer-cases-m3.rb`, M3 brief and this assessment.
Additive index updates only in `docs/soul/HUMAN_REVIEW_GATE.md` and
`skills/_template/REVIEW.md`. No prior M1/M2/Continuity code was edited.

Ruby 4.0.7: case/scorer 12 checks, runner 18 checks, inherited M2 lifecycle 32
checks — **62 grouped checks pass**, plus syntax on all four new Ruby files.
Changed-path resolver requires targeted behavior and Ruby syntax; fulfilled.
Scoped whitespace/diff checks pass. The runner verifier uses fake transports,
clocks and state, not hardware. Focused review led to identity confirmation before
clearing Qwen inflight state, gate/lease source fingerprints, an explicit nested
exception constant, and tested cooldown bounds. Primary verified these fixes;
the reviewer's earlier system-Ruby syntax result is not the pinned test evidence.

## Decision and next gate

Keep Qwen primary. Prefer **direct** AMD review over the evidence-first prepass
for a future optional advisory integration; the latter costs more and adds no
observed outcome benefit here. Do not call this a reliable independent validator
or promote it into automatic task approval. Preserve explicit unavailability,
revision binding and distinct exposure/disposition events.

Before promoting a real reviewer into Soul/LibreChat, address or explicitly bound
the absent-evidence classification failure with fresh cases, and pin/attest all
sampler defaults. Include a no-review Qwen re-answer control: case 01 shows that
reconsideration can fix an answer even after an inaccurate review. Keep format
validation deterministic rather than expecting critique alone to enforce units.
Ten short synthetic cases cannot settle long-context everyday usefulness,
correlated errors, repeated-run variance, mixed-claim verdicts or background
availability. No adapters or developmental claims follow from this result.

M3's requested experiment and documentation are complete. Live production review
delivery, human acceptance and the later LibreChat activation remain open gates.
