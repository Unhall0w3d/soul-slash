# AMD reviewer M3B — candidate comparison and retained evidence

2026-10-13. **Current status: all three v2 windows complete, 144 responses;
runtime/cleanup checks pass. Qwen3.5-9B is the preferred next-stage experimental
candidate, not a qualified validator or production promotion.**

## Completed comparison

The immutable originals score 6/10. All three independent no-review control
branches return identical answers and score 7/10. These are small, synthetic
task scores, not general model rankings.

| AMD reviewer | Assisted answers | Old seeded verdicts | Retained challenge verdicts | Mean AMD response | Whole-device peak VRAM | Peak junction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ministral3-14B Q4_K_M | 6/10 | 7/10 | 4/8 | 4.96 s | 11.03 GiB | 90 C |
| Qwen3.5-9B Q4_K_M, non-thinking | 8/10 | 8/10 | 4/8 | 3.68 s | 7.63 GiB | 82 C |
| Phi-4-14B Q4_K_S | 8/10 | 7/10 | 4/8 | 4.57 s | 10.93 GiB | 90 C |

Twenty-eight AMD responses per model; response timing excludes roughly 3 s of
cooldown before each request, startup, preflight/hashing, other API calls and
teardown. Native tokenizers, output lengths and quantizations differ. Whole-GPU
memory includes desktop allocations; initial desktop usage varied by roughly
0.27 GiB. The settings matched, but these are observed temperature peaks, not
a controlled cooling/undervolting benchmark or continuous maxima.

Excluding the ambiguous parcel/custodian fixture: originals 5/9, controls 6/9,
Ministral-assisted 6/9, both new models 7/9. Both new models correct the same
eligible-record error missed by the control; the archive correction also occurs
without review. No other distinct correction gain was demonstrated. The two
remaining failures omit required kg/L units despite correct numeric values.

All three misclassify all four absence-only seeded claims as contradictions;
both mixed challenge cases also become contradicted. This is a shared review-
process/calibration weakness, not resolved by model substitution. Qwen3.5 had
fewer incoherent findings than Phi-4 in this sample, but also incomplete citations
and some affirmative claims in its error findings. See semantic details below.
Future fixtures must remove the unstated parcel identity and sample-owner joins;
retain these frozen scores and label exclusions, never silently rescore them.

Primary cross-run read-back found identical cases, challenge set, original
answers, source digest, NVIDIA model digest, runtime binaries, sampler, thermal
bounds/cadence, cooldown and applied hardware settings. No prompt/scorer tuning
occurred between these windows. All three report unchanged source/config/runtime/
hardware, reaped owned child, closed8096, settled Qwen request and released lease.
Final independent read-back at approximately18:05EDT: NVIDIA Qwen PID1079343
healthy and idle; AMD services inactive, test port closed,13.59GiB AMD VRAM free.
No new resident reviewer, default, service, memory/Soul/LibreChat delivery or LoRA.

Recommendation: retain Qwen3.5-9B for the next bounded advisory-review comparison.
Its measured resource/latency advantage and one useful correction beyond control
justify that next step, not trusted validation. Investigate evidence-before-verdict
ordering, per-claim judgments and deterministic format/aggregation checks on fresh
unambiguous cases before integration. This is a proposed next experiment, not an
implemented schema change or authorization to promote. Hardware tuning remains
deferred until after LibreChat, as requested.

## V2 preparation and admission history

The user authorized proceeding with a100C junction cutoff, accepting90C edge
and90C memory guardrails. New windows sample every0.5s and abort at or above
those thresholds; polling is not a guarantee against instantaneous overshoot.
Cooldown, headroom, timeout, lease, child ownership and cleanup bounds remain
unchanged. LACT/BIOS/RAM settings are untouched. The v1 runner and brief are
retained beside its original protocol with matching original hashes.

V2 records the applied clock/voltage, power cap and all six driver critical/
emergency limits before/after. Missing, invalid or nonpositive driver-limit
readings fail closed. Focused Sol review found no changed lifecycle regression;
its missing-limit attestation concern was repaired before live work. Luna's
synthetic tests exercise exact90/100/90 boundaries, nonfinite/missing sensors,
resource bounds and asynchronous monitor-failure teardown/join. M3B verifier
18/18, inherited M2 32/32, M3 18/18 and fixture10/10 pass; unchanged downloader
6/6 evidence retained:84 grouped checks total. Changed Ruby syntax and required-
check routing pass. No production or M1/Continuity code was changed for v2.

The RAM baseline is user-supplied dmidecode:3800MT/s configured. MCLK1900MHz
follows from that rate; FCLK1900MHz is conditional on the user-reported1:1 ratio,
not independently measured. This may affect RAM/CPU-sensitive timings but no
speedup is attributed without an untuned control. Every candidate uses the same
existing settings. Hardware tuning comparisons remain deferred until LibreChat.

At21:34UTC the advisory gate still refused a foreign allocation. Opera initially
used529.8MiB; after the operator closed a tab it was below512MiB, but the ChatGPT
desktop process PID23165 was observed at516.1MiB. No application was stopped and
the existing512MiB foreign-client guard was not relaxed. Qwen PID1079343 is
healthy/idle; AMD model services inactive; pilot port8096 closed. This is an
admission prerequisite, not a model failure. Closing the preview cleared this
admission, allowing the first v2 window below.

## V2 matched baseline — complete

Evidence:
`Soul/runtime/qualification/amd-reviewer-m3b-ministral14-20261013T213846Z-20261013-2072253-boidmp`

All48 responses completed; Ministral41/41 layers offloaded, startup2.75s.
Frozen scores: original6/10, no-review reconsideration7/10, assisted6/10;
old seeded verdicts7/10, retained eight-case challenge4/8. One corrected and
one mechanically spoiled answer, with the latter being the previously flagged
ambiguous parcel/custodian fixture. These counts do not establish a net reviewer
benefit. Preserve the raw score and interpret that ambiguity separately.

Read-only semantic audit: excluding the parcel case, originals5/9, control6/9,
assisted6/9; the one correction is shared with control. Old supported seeds4/5,
contradicted3/3, insufficient0/2; challenge supported2/2, contradicted2/2,
insufficient0/2, mixed0/2. All four unsupported definite values were called
contradicted for lack of evidence; both mixed answers lost that distinction.
Original case5 rejects invalidR-21 but confidently suggests wrong-siteR-17
instead of eligibleR-44; Qwen remainsR-21. Cases3/6 omit required units, which
the reviewer misses despite correct numeric quantities. Challenge4's manager-
to-owner join is implicit and cites an incomplete evidence chain; challenge7
has an empty evidence_refs list for its date finding. Nominal verdict accuracy
therefore must not be presented as full semantic grounding accuracy. No prompt
or scoring change is made from these observations.

AMD28 calls:138.76s total,2.40–9.81s each,21936 input/3780 output tokens;
Qwen20 calls:31.51s total,5713 input/334 output. AMD cooldowns add84.19s.
These response timings exclude startup, preflight/hashing, other API calls and
teardown. Sampled peaks80C edge/90C junction/68C memory; whole-device VRAM
peak11843567616 bytes. No thermal abort at the approved v2 limits.

Gate reports successful foreground completion. Before/after source/config,
runtime and hardware settings unchanged; own lease gone, endpoint8096 closed,
Qwen request settled. Primary read-back confirmed Qwen idle and8096 closed;
the owned PID2073004 no longer exists. An inline read-back command's rescue
syntax was incorrect and printed ESRCH rather than a Boolean; this diagnostic
error did not change state or invalidate the independent cleanup receipts.
Final snapshot21:43:50UTC:55/67/58C,3110649856 bytes total AMD VRAM used.

Before candidate2, admission refused Opera PID17197 at777.8MiB. Operator was
asked to close it completely for the remaining two windows; no eviction,
guard change, automatic retry of a model result or background waiter was added.

## V2 new candidates — complete

Qwen3.5 evidence:
`Soul/runtime/qualification/amd-reviewer-m3b-qwen35-20261013T215417Z-20261013-2092430-65cqlm`

All 48 responses complete; native non-thinking template and actual sampler
attested, 34/34 layers offloaded. Startup2.35s. AMD28 calls103.15s total,
1.98–7.54s each,21686 input/3599 output tokens; cooldown84.19s. Qwen20 calls
30.93s,5506 input/334 output. Sampled edge/junction/memory maxima73/82/66C;
peak VRAM8192077824 bytes. No observed swap-out delta. Owned PID2093060 absent,
cleanup flags all pass. Final snapshot21:58:38UTC:53/65/54C.

Semantic review confirms the R-44 correction is grounded: it excludes invalid
R-21 and wrong-site R-17. Its evidence_refs omit one row discussed in its rationale.
Parcel is preserved under the frozen oracle, but the identity ambiguity remains.
All unsupported seeds and mixed cases are misclassified as described above.
Challenge4 includes correct statements as findings and an empty evidence_refs
entry; supported verdicts do not prove all accompanying output is compliant.

Phi-4 evidence:
`Soul/runtime/qualification/amd-reviewer-m3b-phi4-20261013T215944Z-20261013-2097875-shnhtq`

All 48 responses complete; native template and sampler attested,41/41 layers
offloaded. Startup3.11s. AMD28 calls128.06s total,2.17–11.11s each,17971 input/
3978 output tokens; cooldown84.19s. Qwen20 calls31.50s,5689 input/334 output.
Sampled maxima81/90/72C; peak VRAM11737911296 bytes. Global swap-out increased
9687 pages (37.84MiB), below the256MiB bound; attribution to this process is not
established. Owned PID2098646 absent; all cleanup flags pass. Final snapshot
22:04:41UTC:56/69/64C.

Phi's R-44 correction is grounded, but its parcel review falsely asserts that
the custodian ID and named occupant differ; Qwen preserves the original anyway.
It emits three affirmative findings for supported challenge2, includes historically
true but inapplicable fee facts among old seed7's findings, and calls an approver
unsupported in its rationale while assigning a contradictory overall verdict.
These are additional output-coherence problems beyond the shared calibration
failure. No semantic review result grants authority or changes the source answers.

## Candidates and source basis

| Candidate | Artifact | Disk bytes | Rationale / status |
| --- | --- | ---: | --- |
| Ministral3-14B | Existing publisher Q4_K_M | 8,239,593,024 | Complete v2 baseline; partial v1 retained |
| Qwen3.5-9B | bartowski Q4_K_M | 6,169,341,984 | Complete v2; preferred next experimental candidate |
| Phi-4-14B | Microsoft Q4_K_S | 8,440,762,560 | Complete v2; no promotion |

Sources: [Qwen official model card](https://huggingface.co/Qwen/Qwen3.5-9B),
[pinned quantizer manifest](https://huggingface.co/bartowski/Qwen_Qwen3.5-9B-GGUF/tree/182be2fd6c7bc44887d88a91cb03ff009cc9f549),
[Microsoft official GGUF/card](https://huggingface.co/microsoft/phi-4-gguf/tree/6edc2ef6664b739a8e11e62f2672ff6afe0c15ac).
Exact digests/revisions are in `scripts/support/amd_reviewer_assets_m3b.json`.
Files are under `/home/bhones/ai_models/amd-reviewer-m3b`; total 14,610,104,544
bytes. No credentials, gated downloads, projector, runtime install or registry
change. Qwen's documented template control disables thinking for this bounded
short-response experiment; it is not a test of extended-reasoning capability.
Phi-4's training age/factual benchmark limitations remain reasons to test against
supplied evidence, not reasons to assume quality. Different quantization formats
and native templates mean this tests practical model configurations, not weights
in isolation. Weight size alone does not establish VRAM fit.

Also considered [official Qwen3.8-27B](https://huggingface.co/Qwen/Qwen3.8-27B):
[its Q4_K_M artifact](https://huggingface.co/bartowski/Qwen3.8-27B-GGUF) is about
17.44 GB, exceeding this fully GPU-resident allowance before runtime memory.
No smaller official Qwen3.8 variant was found in Qwen's current collection.
Gemma3-12B was a possible alternative, but the two selected public candidates
avoid a new gated upstream license/account step. Phi4-reasoning-plus is a future
distinct protocol option; it should not be forced into a 768-token direct-output
budget and then judged as though fully exercised.

## Original v1 implementation and deterministic evidence (retained)

New bounded runner: `scripts/compare-amd-reviewer-m3b.rb`; unchanged M2/M3
lifecycle inherited for lease, control lock, resource monitor, quiescence and
teardown. Candidate-specific loader checks actual model path, template digest,
full offload and owned DRM allocation. Qwen3.5's non-thinking suffix is verified.
Forty-eight calls per candidate: 10 control re-answers, 10 AMD reviews of the
originals, 10 Qwen revisions, 10 old seeded reviews, 8 fresh seeded reviews.
Same M3 v2 original answers and frozen fixture digest; independent branches,
rotated old and fresh case order, no oracle exposure. Actual returned sampler
settings are checked, including explicitly zero presence/frequency penalties.
No new evidence is delivered to Soul, ordinary memory or LibreChat.

79 grouped deterministic checks passed with Ruby4.0.7:

- inherited M2 lifecycle: 32;
- inherited M3 comparison: 18;
- new M3B cases: 10;
- new M3B substitution/control boundaries: 13;
- downloader temporary-fixture safety: 6.

Six new Ruby files passed syntax; manifest JSON parses; changed-path resolver
requires `targeted_behavior` and `ruby_syntax`, satisfied; scoped whitespace and
tracked diff checks pass. Sol read-only review found and prompted direct
historical-fixture digest enforcement and rotation of fresh cases. Primary
also hardened the completed downloader for subsequent invocations with an
exclusive lock and non-overwriting hard-link final publication; tests cover
lock conflict, mismatches, symlinks and a competing final file. The actual first
downloads used the earlier one-invocation path and both passed exact digest/size
checks; the hardened final-publication path has fixture evidence, not a second
network-download claim.

## Retained live attempt — not a completed comparison

Evidence:
`Soul/runtime/qualification/amd-reviewer-m3b-ministral14-20261013T211016Z-20261013-2031531-t68zr5`

Ministral loaded 41/41 layers on AMD in 2.78 seconds. Ten paired old cases and
seven of eight fresh reviews completed: 47 valid responses, with the 48th request
interrupted by the unchanged thermal guard. Peak sample **80 C edge / 90 C
junction / 68 C memory**; the edge threshold triggered the stop. Peak whole-device
VRAM was 11,729,383,424 bytes. The samples before the triggering 2-second sample
were 53/66 C; sampled maxima are not an assertion of continuous peak measurement.
The failed partial stream, original prompts, protocol, runtime/source hashes,
bindings and monitor samples remain retained. No final aggregate summary was
produced by the runner; do not score the incomplete eighth review or promote
this attempt as a completed baseline.

Diagnostic subset only, unchanged frozen scoring:

- originals 6/10; no-review reconsideration 7/10; review-assisted revisions 6/10;
- old seeded verdicts 7/10; both unsupported claims again called contradicted;
- fresh completed seeds 4/7: two supported and two contradicted correct, both
  unsupported called contradicted, one mixed called contradicted; eighth unscored.

One apparent spoiled original (parcel-custodian join) exposes fixture ambiguity:
the records associate C-8 with an office and name its occupant, without explicitly
identifying the occupant as C-8. The frozen oracle assumes that identity. The
reviewer's concern is legitimate, but its assertion of a positive contradiction
and replacement of a requested name with `C-8` go beyond that evidence. Keep the
mechanical score, flag the ambiguity, and do not claim unambiguous spoilage from
this case. Do not retroactively alter the historical M3 fixture/result.

47 completed response timings total 165.88 seconds plus 81.16 seconds cooldown;
startup, preflight/hashing, other API calls and the interrupted request are not
included. 27 completed AMD calls used 21,036 input / 3,522 output tokens; 20 Qwen
calls used 5,766 / 334. This cannot rank the new candidates: neither ran.

## Cleanup and thermal clarification

Temporary AMD PID2032425 was reaped; endpoint8096 closed; owned lease gone.
All 70 source/config evidence hashes and runtime binaries compared unchanged;
NVIDIA Qwen PID1079343 remains active, healthy, single4096 slot idle. Its observed
allocation was5296MiB. Gemma/Dev services remain inactive. Independent primary
read-back at21:17:14UTC confirmed PID absence and primary health. No restart,
default, power/fan/clock/voltage or service mutation was performed by Codex.

After the user questioned the test cutoff, read-only hardware inspection found:

| Sensor | Driver `crit` | Driver `emergency` |
| --- | ---: | ---: |
| Edge | 100 C | 105 C |
| Junction | 110 C | 115 C |
| Memory | 100 C | 105 C |

These are the actual card's sysfs values, not the qualification limits.
[Kernel documentation](https://docs.kernel.org/gpu/amdgpu/thermal.html) defines
critical max and emergency ASIC shutdown separately. Thus the user's110C
junction recollection is supported. This attempt stopped conservatively below
critical limits; it does **not** establish hardware overheating, throttling or
damage. The110C junction value must not be applied to edge or memory sensors.

The operator also reported personally lowering maximum core clock to2400MHz.
Read-back confirms OD_SCLK500–2400MHz, voltage offset0mV, power cap281W. Preserve
those settings. Their change time relative to earlier runs is unknown; don't
attribute thermal differences to the clock cap or claim a matched before/after
hardware trial. Capture applied clocks and limits before the next window.

The operator further reports a fan curve reaching100% at75C, a Thermaltake P5
case and a New York basement environment; previously observed100–110C hotspot
temperatures while running Empyrion at a240FPS cap. These are operator-provided
conditions/history, not this run's measurements. The fan-curve controlling
sensor, ambient temperature and under-load fan behavior were not independently
attested. Preserve the existing fan curve; no tuning was performed by Codex.

## V1 next-boundary recommendation (historical; superseded above)

No further inference this turn after the predeclared stop. Qwen3.5 and Phi4 are
ready for a future controlled window, not qualified or promoted. Recommended
discussion: replace the arbitrary80/95 test envelope with explicit hardware-
informed margins (e.g.90C edge/100C junction/90C memory), keeping cooldown,
headroom, ownership and cleanup guards and tighter sampling. These are proposed
harness choices, not manufacturer-recommended operating targets or an approved
safeguard change. No limit has been raised. Preserve this failed attempt and
freeze a new protocol if the envelope changes; do not silently rerun or rescore.
