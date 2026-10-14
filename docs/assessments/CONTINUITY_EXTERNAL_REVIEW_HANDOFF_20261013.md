# Soul Continuity Lab progress and independent review handoff

**As of October 13, 2026, through Continuity A23 and AMD reviewer M3C.**

Prepared for the original ChatGPT planning conversation. This is a self-contained
account of the revised plan, implementation, comparisons, limitations, and open
decisions. The repository references provide a route to supporting evidence;
they are not required to understand the report. No credentials, private
conversation transcripts, or raw runtime directories are included.

## What we would like reviewed

Please challenge the architecture, experimental design, interpretations, and
proposed next steps rather than merely endorsing the work. In particular: have
we separated failures of context, retrieval, reasoning, output contracts, and
evaluation correctly? Are we adding machinery that helps the experiment but
does not help the user? What is the smallest useful system we should actually
put in front of the operator next?

Our priorities are **usability and usefulness first**, followed by research
questions that can be investigated within the environment we actually have.
This is a personal workstation project, not an always-on research laboratory.
Suggestions are welcome; this handoff does not authorize execution or promotion.

## 1. Where we stand

We have a bounded, inspectable local conversation candidate and an implemented
connection adapter for a controlled LibreChat trial. We have not completed the
actual LibreChat browser trial or established everyday conversational reliability.

The main findings are:

- Giving the model runtime-generated records of its completed actions helped a
  narrow rollover task. Supplying recent dialogue and complete, small evidence
  bundles then substantially improved practical results.
- Those changes deliberately moved responsibility from model-initiated recall
  toward the surrounding software. They improve the practical condition while
  changing what the experiment can tell us about self-authored memory.
- Once complete evidence was present, several failures remained ordinary
  constraint, comparison, and answer-quality errors. More memory would not
  explain those particular failures.
- Larger quantized models could run with NVIDIA/RAM offloading, but the tested
  configurations did not provide a decisive usefulness improvement for their
  latency. The original Qwen3 8B remains the selected experimental baseline.
- A separate AMD reviewer can run while Qwen remains on NVIDIA, with bounded
  resource admission, cancellation, and cleanup. That operational result is
  stronger than the evidence for the reviewer's usefulness.
- The latest fresh reviewer comparison found no unique corrections beyond a
  no-review reconsideration control. Moving the verdict later did not improve
  calibration. A stricter claim-and-citation protocol rejected many reviews and
  reduced completed, correct outcomes.

No larger model, reviewer protocol, LoRA, automatic review delivery, ordinary
Soul-memory integration, or LibreChat connection has been promoted through this
work. The latest experimental jobs completed and cleaned up. Runtime statements
here refer to their retained closeout evidence, not a new host inspection made
while writing this report.

## 2. Original question and the revised plan

The original question was approximately:

> Can a fixed local model use optional self-authored records to sustain useful,
> correctable behavior across context rollover and runtime restart?

The initial adaptation put this inside Soul, using native Ruby and a small
append-only journal rather than introducing another application stack. The
initial evidence environment was a bounded text corpus, not unrestricted web
browsing. There was no training, idle-time reflection, autonomous scheduler,
or automatic transfer into ordinary Soul memory.

Early A0–A12 work established journaling, replay, isolated foreground workers,
tool boundaries, model identity checks, actual-token context packing, and
retained failure evidence. It also exposed concrete problems: message ordering,
context limits, timeouts, fragile retrieval, repeated actions, and information
lost when older action/result pairs were removed from the prompt. Some were
software defects; others persisted after the infrastructure behaved as intended.

At A13, the operator explicitly chose the practical revision: usefulness first,
with research questions adjusted to the available hardware and resulting system.
The original minimal condition remains available, with its failed and successful
results preserved. It has not been retroactively declared successful.

### What changed, and what each change means

| Change | Practical purpose | Consequence for interpretation |
| --- | --- | --- |
| Runtime action/result receipts, A13 | Retain what actually happened after full tool exchanges leave context | The model no longer has to reconstruct all current-task progress from optional notes. This is software-provided operational continuity. |
| Ranked lexical retrieval, A17 | Recover useful documents when exact all-word matching returns nothing | Retrieval quality is partly a property of the search implementation, not just the model's query skill. |
| Automatic recent dialogue, A17 | Keep short conversational callbacks and corrections accessible | Successful recall no longer demonstrates that the model independently chose to save or retrieve those exchanges. |
| Complete small evidence bundles and answer-only execution, A18 | Remove unreliable search/tool loops from the practical chat path | This tests answering with supplied evidence, not autonomous retrieval. Evidence injection and tool removal changed together. |
| Chronological chat presentation, A19 | Preserve ordinary user/assistant ordering | A presentation improvement, not additional evidence or an inferred summary. |
| Explicit verified selection helper, A21 | Reliably solve supported structured filtering/comparison tasks | Correctness comes from deterministic computation within a narrow contract, not improved model arithmetic. |
| LibreChat transport adapter, A22 | Make the bounded candidate usable through a familiar interface | The interface does not increase the model's context, grant tools, or establish production readiness. |
| Optional detached AMD reviewer, M0–M3C | Test whether a second model improves answers and later supports developmental experiments | Review is additional, unendorsed evidence. Availability, validity, truth, usefulness, and acceptance are separate questions. |

The revised question is therefore broader and more practical: **can a bounded
model-plus-software system maintain useful, inspectable conversational continuity,
and which mechanisms actually contribute to it?** The original memory question
can still be studied with explicit comparison conditions. It is not answered
merely by making the practical interface work.

Sources: [adaptation history](../soul/CONTINUITY_LAB_ADAPTATION_PLAN.md),
[A9–A12 results](CONTINUITY_LAB_A9_A12_REVIEW.md),
[A13 approved revision](../soul/CONTINUITY_LAB_A13_BRIEF.md).

## 3. Hardware and the practical execution path

The machine has a Ryzen 7 5800X, 64 GB installed RAM, an NVIDIA GTX 1070 FE with
8 GB VRAM, and an AMD Radeon RX 6900 XT with 16 GB VRAM. The normal experimental
primary is **Qwen3-8B Q4_K_M**, served through the existing Pascal-compatible
llama.cpp build. The later AMD comparisons use a separate Vulkan runtime.

The operator reports RAM configured at 3800 MT/s and a matched fabric ratio.
That establishes a 1900 MHz memory clock; a 1900 MHz fabric clock follows only
if the reported 1:1 relationship holds. We did not measure a performance gain
attributable to that tuning.

The A19/A22 practical profile uses a 4096-token model context, a 3072-token input
ceiling, and a 768-token output ceiling, with thinking disabled. Its input is:

1. The current request.
2. The complete selected small corpus, including source identifiers, revisions,
   hashes, and provenance. The corpus limit is eight documents and 8192 encoded
   bytes, not permission to exceed the token budget.
3. Up to three complete recent exchanges, also bounded to 4096 encoded bytes.
   Actual token packing may retain fewer exchanges.

Old complete exchanges can be removed first. Essential evidence that cannot fit
causes an explicit refusal rather than silent source truncation. A replay
manifest records what was actually supplied. A complete stored journal is **not**
the same thing as complete model recall.

The A17 retrieval option is deliberately modest: exact matches keep their old
ordering, and only a search with no exact hits falls back to deterministic
partial-term ranking with conservative normalization. It is not an embedding
database, semantic-search model, or hidden web retrieval mechanism.

This practical path permits one answer-generation call and no tool actions. The
restriction is enforced through configuration, parsing, grammar, and broker
boundaries, not merely a request in the prompt. Earlier agentic qualification
profiles remain separate; they provide bounded search/read/note operations.

### What the different records mean

| Record | What it establishes | What it does not establish |
| --- | --- | --- |
| Runtime journal and tool receipt | An observed event, attempted action, outcome, revision, or failure | Understanding, a successful overall task, or authorization for a future action |
| Model-authored note | What the model elected or was asked to record | Verified fact, endorsed memory, or learned policy |
| Input/replay manifest | Which source revisions and dialogue were supplied | That the model attended to or understood them |
| Generated answer or review | A particular model output under a recorded configuration | Truth merely because it has valid JSON or citations |
| Later behavior | What the system subsequently did in that test | A durable trait without further evidence |

A13 receipts preserve factual current-event action/result metadata when full
pairs are evicted. They do not retain the source text, search snippets, or note
contents, and they are not automatic cross-event memory. Cross-event access in
the agentic profiles uses the existing history, notes, and corpus tools.

Journal contracts include exact-request idempotency, rejection of a changed
payload under the same identity, revision checks, and retention of uncertain
inference intent. They do not claim exactly-once effects in arbitrary external
systems. A fresh isolated worker per request is also not a cold model restart:
the underlying model server can remain resident.

Sources: [A13](CONTINUITY_LAB_A13_REVIEW.md),
[A17](CONTINUITY_LAB_A17_REVIEW.md),
[A18](CONTINUITY_LAB_A18_REVIEW.md),
[A19](CONTINUITY_LAB_A19_REVIEW.md),
[connection limits](../guides/CONTINUITY_LIBRECHAT_HANDOFF.md).

## 4. Results after the practical revision

These are small development comparisons, not a single cumulative benchmark.
The case sets changed between stages. Callback measures often form a subset of
factual tasks and must not be added as independent successes.

### Receipts, retrieval, and conversation

| Stage | Comparison or task | Result | Main lesson |
| --- | --- | --- | --- |
| A13 | Current-event receipts, visible-history and rollover cases | Final receipt-pair presentation: 4/4 strict cases, 20 generations | Compact observed progress can survive rollover in this narrow task. Earlier sizing and receipt-array failures remain recorded. |
| A14 | Directed note lifecycle and subsequent source use | 4/4 note cases; successful source revision 3/3 after two retained prompt-sensitive failures | Notes and fresh workers can support these directed tasks. This does not demonstrate spontaneous note selection or model-server restart continuity. |
| A15 | Less-prescriptive practical tasks plus generic conversation | All 12 requests received replies; mechanical screen 4/12; six source-dependent tasks and the callback failed | Reply completion is not practical success. Relevant history was available but was not searched. |
| A16 | Baseline versus explicit retrieval guidance | Factual 1/10 in each; callbacks 0/4 in each; 36 versus 50 model calls | Better instructions alone did not overcome the practical retrieval/recall problem. |
| A17 | Exact search / ranked search / ranked search plus recent dialogue | Factual 1/13 → 2/13 → 7/13; callbacks 0/5 → 0/5 → 4/5 | Automatic recent context contributed much more than this lexical-ranking change in the tested package. |
| A18 | Agentic retrieval versus complete evidence plus answer-only mode | Factual 7/16 → 13/16; callbacks 4/6 → 5/6; replies 21/24 → 24/24; calls 59 → 24 | Removing the retrieval burden improved outcomes and reduced calls. Three factual errors remained despite complete evidence. |
| A19 | Direct envelope versus chronological chat, same evidence policy | Factual 16/20 → 17/20; callbacks 6/7 → 7/7; grounded unknown answers 4/4 in both | One correction/callback improved. Three shared initial selection errors remained. |
| A20 | A19 versus general filter-then-compare guidance | Clean factual answers 20/28 → 21/28; fresh clean selections 3/8 → 4/8; callbacks 7/7 in both | Too little gain to adopt another prompt layer; A19 remains the baseline. |

A13's successful rollover prompts were 2027 and 2028 tokens against the then
2048-token input ceiling. That demonstrates the intended visibility boundary,
not generous headroom. A14 used actual fresh workers and reread sources; its
successful seven cases used 23 generations, while all retained A14 attempts
used 39.

A17 scheduled 60 requests, executed 57, and skipped three after prerequisite
failures, using 144 generations. A18 used 83 generations; A19 used 56. These
counts help distinguish improved answers from simply spending more calls.

A20 also illustrates why we retained full answers rather than only keyword
scores. The guided condition reached 22/28 correct final conclusions, but one
opened with a false claim; only 21/28 were clean answers. Guidance added 3371
input tokens and 110 output tokens across its comparison condition, without
resolving the inherited selection failures.

Generic conversation was coherent enough for the small trials, but often
formulaic, presumptive, or unnecessarily evaluative. Examples included assuming
a walk had been pleasant, making an unsupported personal flourish, or repeatedly
closing the conversation. This is not evidence of a preferred persona or a
successful open-ended usability trial.

The remaining selection errors were specific and checkable: choosing an eligible
but more expensive option, selecting an item below a minimum requirement, or
miscomparing values already present in the prompt. Some occurred on the first
turn with no prior dialogue. Those cannot be explained by forgotten earlier
conversation or missing retrieved evidence.

Sources: [A14](CONTINUITY_LAB_A14_REVIEW.md),
[A15](CONTINUITY_LAB_A15_REVIEW.md),
[A16](CONTINUITY_LAB_A16_REVIEW.md),
[A17](CONTINUITY_LAB_A17_REVIEW.md),
[A18](CONTINUITY_LAB_A18_REVIEW.md),
[A19](CONTINUITY_LAB_A19_REVIEW.md),
[A20](CONTINUITY_LAB_A20_REVIEW.md).

### A21: narrow deterministic assistance

We implemented an explicit verified-selection library and foreground CLI. It
supports a constrained class of catalog extraction, filtering, and comparison
with exact rational arithmetic, complete-source checks, revision/hash binding,
and quoted source spans. Malformed, partial, or ambiguous input is refused.
Any model-proposed table must match the extracted source values.

It returned the correct result on all eight retrospective A20 catalog fixtures.
That is not an 8/8 language-model improvement: the structured request was already
specified, and the computation was deterministic. Natural-language interpretation
and automatic chat routing to the helper are not qualified. A verified result
is kept distinct from any unverified generated explanation.

There were 59 grouped deterministic checks and no live inference in this stage.
The helper remains an explicit CLI, not a hidden automatic addition to A19.
See [A21](CONTINUITY_LAB_A21_REVIEW.md).

## 5. Larger primary models on NVIDIA and system RAM

Before connecting LibreChat, we tested whether more capable models could improve
the practical result through offloading. The 14B candidate was **Ministral 3
14B Instruct**, not Qwen 14B. The other candidates were Qwen3.6-35B-A3B and
Qwen3-30B-A3B-Instruct-2507. MoE total parameter counts should not be confused
with active parameter counts.

Each configuration received 15 scored turns and one warmup: 12 turns with
factual expectations and three qualitative conversation turns. The evidence,
context policy, and answer-only contract were shared. Native templates,
tokenizers, and model-appropriate samplers differed. Later conversation inputs
included each model's own earlier replies. This compares practical configurations,
not parameter counts in isolation.

| Initial configuration | Fully correct factual turns | Median answer | Median first token | Peak whole-device NVIDIA VRAM |
| --- | ---: | ---: | ---: | ---: |
| Qwen3-8B Q4_K_M, existing full GPU | 9/12 | 2.08 s | 0.91 s | 5301 MiB |
| Qwen3.6-35B-A3B UD-Q4_K_M, experts on CPU | 10/12 | 29.11 s | 28.04 s | 2579 MiB |
| Ministral-3-14B-Instruct-2512 Q4_K_M, automatic layer fit | 8/12 | 8.50 s | 4.79 s | 7051 MiB |
| Qwen3-30B-A3B-Instruct-2507 Q4_K_M, experts on CPU | 10/12 | 29.81 s | 27.99 s | 1473 MiB |

The CPU-expert placement underused available VRAM, so a separately declared
follow-up changed both automatic layer placement and flash-attention selection.

| Follow-up configuration | Fully correct factual turns | Median answer | Median first token | Peak whole-device NVIDIA VRAM |
| --- | ---: | ---: | ---: | ---: |
| Qwen35, automatic layers and FA auto | 8/12 | 21.46 s | 20.53 s | 6893 MiB |
| Qwen30, automatic layers and FA auto | 9/12 | 19.83 s | 18.48 s | 7109 MiB |

The follow-up reused development cases and changed two flags. It is not an
independent held-out comparison or evidence isolating either flag. Identical
seeds do not guarantee identical output across backend/kernel changes.

All 96 generation calls completed normally across the six configurations, without
truncated inputs or output-limit failures. The larger models introduced different
errors, including falsely denying that listed prices existed and giving a
correct conclusion preceded by a contradictory claim. Correct keywords alone
would have overstated their results. Conversely, rigid screens rejected some
valid comma-formatted numbers or synonymous unknown answers; the original
screens and separate full-answer assessments were both retained.

The best initial MoE scores added one factual success over Qwen8 at roughly
14 times its median response latency. The follow-up improved speed, not the
observed accuracy. Qwen30 could decode about as fast as Qwen8, but prompt
processing still dominated its delay before the answer.

System-wide swap-out increased by about 3.10 GiB during the first window and
1.84 GiB during the second; the full interval including transitions was about
6.05 GiB. These are cumulative host counters, not simultaneous occupied swap
or exclusive model attribution. We cannot call this a paging-free solution.
Concurrent gaming was not qualified. The original Qwen service was restored
and checked healthy and idle after the experiments.

**Decision:** retain Qwen8 for the first controlled LibreChat trial. These results
do not establish a ceiling for the candidate families: one quantized asset,
one seed, a small synthetic workload, and non-thinking answer-only operation
were tested. Reasoning-enabled modes, other quantizations/runtimes, larger
contexts, and tool use remain different experiments.

Source: [A23 comparison and restoration evidence](CONTINUITY_LAB_A23_REVIEW.md).

## 6. The AMD reviewer and prospective LoRA work

The reviewer proposal is deliberately separate from the primary conversation
runtime. The initial objective is a useful, optional second opinion, not an
authority layer and not training. No LoRA has been trained or loaded in any
reported comparison.

### M0–M1: provenance, availability, and lifecycle

The implemented detached workflow binds a review to an exact source event,
source-answer revision, evidence revision, request digest, runtime-attested
model identity, and configuration digest. A later answer edit does not erase
the review: it makes that review stale relative to the new answer.

The original response schema distinguishes `supported`, `contradicted`,
`insufficient_evidence`, and `mixed`, with findings, evidence references,
confidence, rationale, proposed checks, and omissions. Valid references bind
to supplied evidence; they do not prove the finding follows from it.

Reviewer availability cannot silently alter the primary task's contract:

> Reviewer unavailable. Request retained for later review.

Advisory work may proceed explicitly unreviewed under its ordinary policy.
An operation requiring independent validation remains pending. There is no
silent fallback reviewer, indefinite wait, or claim that review occurred.

The durable lifecycle distinguishes queued, leased, running, completed, failed,
canceled, indeterminate, and expiration outcomes. Deadlines and attempt identities
fence late results. Uncertain interrupted work is not automatically requeued.
The store is owner-private and bounded; retention does not require a background
listener or cleanup daemon. M1 passed 269 grouped deterministic checks using
fake review execution; that stage did not establish GPU operation or quality.

### M2: actual AMD operation

Ministral 3 14B Q4_K_M loaded all 41 layers onto the AMD card while the primary
Qwen remained resident on NVIDIA. Three initial review calls completed in
approximately 3.30–5.24 seconds. Cancellation during a fourth streaming call
reaped the owned runtime in about 0.20 seconds; reload and a subsequent review
also succeeded. Load/reload took about 2.75 seconds.

Peak whole-device AMD VRAM was about 10.83 GiB; peak junction temperature was
80 C. This qualified a bounded quiet-host load/cancel/reload path, not concurrent
gaming, arbitrary shared-runtime cancellation, or survival of every possible
supervisor failure.

Quality concerns appeared immediately. An absent warranty was labeled
`contradicted` even while the rationale described insufficient evidence. A
structurally accepted response was not therefore a calibrated factual review.

Sources: [M0–M1](AMD_REVIEWER_M0_M1_REVIEW.md),
[M2](AMD_REVIEWER_M2_REVIEW.md).

### M3: initial answer improvement comparison

Ten original Qwen answers scored 6/10. Qwen self-review followed by revision
scored 7/10; direct AMD review followed by Qwen revision scored 8/10; an additional
AMD evidence-first step followed by review and revision scored 7/10. No originally
correct answer was spoiled in this small comparison.

That was suggestive, not decisive. Both reviewers failed both seeded
insufficient-evidence cases. Direct AMD review plus revision cost about 7.92
additional seconds per task including cooldown; the evidence-first chain cost
about 11.95 seconds. More intermediate stages did not improve the result.
The completed comparison used 100 generations. An earlier thermal-aborted
attempt was retained separately.

### M3B: changing the reviewer model

We then compared three AMD models against the same ten frozen original answers,
including a no-review reconsideration control for each. Each model window used
48 calls: controls, reviews, revisions, and seeded review cases; 144 calls total.

| AMD reviewer | Assisted final answers | Old seeded verdicts | Retained challenge verdicts | Mean AMD response | Peak device VRAM | Peak junction |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Ministral 3 14B Q4_K_M | 6/10 | 7/10 | 4/8 | 4.96 s | 11.03 GiB | 90 C |
| Qwen3.5-9B Q4_K_M, non-thinking | 8/10 | 8/10 | 4/8 | 3.68 s | 7.63 GiB | 82 C |
| Phi-4-14B Q4_K_S | 8/10 | 7/10 | 4/8 | 4.57 s | 10.93 GiB | 90 C |

The originals scored 6/10 and all three independent no-review controls scored
7/10. Qwen3.5 and Phi-4 each made the same one additional correction beyond
control. An ambiguous parcel/custodian fixture was identified; excluding it
leaves originals 5/9, controls 6/9, Ministral-assisted 6/9, and the other two 7/9.

All models mislabeled four unsupported seeded claims as contradicted and flattened
both mixed challenge cases to contradicted. Seven of the eight challenge cases
had already appeared in a thermal-aborted attempt, so we describe this as a
retained challenge/retest set, not eight wholly unseen cases.

Qwen3.5 was selected as the next experimental reviewer candidate because it was
faster and used less memory and heat in this comparison. It was not established
as a reliable validator or promoted to production.

Sources: [M3](AMD_REVIEWER_M3_REVIEW.md),
[M3B](AMD_REVIEWER_M3B_REVIEW.md).

### M3C: could we improve the validation protocol?

The latest experiment used Qwen3.5-9B and fourteen fresh synthetic source answers:
three each for supported, contradicted, insufficient-evidence, and mixed verdicts,
plus two missing-unit cases. These answers were deliberately authored, not sampled
from Qwen. That makes this a seeded diagnostic, not an estimate of naturally
occurring error frequency.

Each case had an independent no-review reconsideration control and three review
conditions, with rotated ordering:

1. The current review format.
2. The same format with the verdict emitted after omissions/findings.
3. Per-field claim judgments, exact source-value and quotation checks, complete
   claim coverage, deterministic verdict aggregation, and separate format checks.

| Condition | Correct semantic verdicts /12 | Strict final answers /14 | Invalid reviews | Unique corrections beyond control |
| --- | ---: | ---: | ---: | ---: |
| No-review reconsideration | Not applicable | 12 | Not applicable | Not applicable |
| Current reviewer | 6 | 12 | 0 | 0 |
| Verdict after findings | 6 | 11 | 0 | 0 |
| Claim-level checks | 3 | 4 | 8 | 0 |

Original strict answers scored 3/14. The substantial gain to 12/14 happened
without AMD review. Crediting that gain to the reviewer would have been wrong.

The window completed 90 generations: 42 AMD reviews and 48 Qwen controls or
revisions. Eight planned revisions were explicitly skipped after invalid reviews,
accounting for all 98 planned slots. Every issued call returned a complete,
parseable response. The eight invalid reviews stay in the denominators; they
are not silently discarded or replaced by successful control answers.

Three details matter:

- **Unsupported is not false.** Both older protocols called every unsupported
  and mixed case `contradicted`, sometimes with high confidence. Moving the verdict
  to the end was verified in the actual output but did not change this pattern.
  Output order is not evidence about hidden internal reasoning order.
- **A real quotation need not support the conclusion.** One claim-level review
  quoted “Its seal log does not include a ballot count.” exactly, then treated
  the asserted count of 47 as contradicted. Citation integrity passed; entailment
  failed. All eight invalid reviews lacked a mandatory citation for a positive
  judgment. Some raw judgments were semantically right but still unusable under
  the declared contract.
- **Detecting a format defect did not ensure correction.** Deterministic checks
  identified missing units and supplied the findings to Qwen. It still returned
  `4.25` and `16L` rather than `4.25 kg` and `16 L`. This is a downstream format
  failure under a string-only answer schema, not evidence of a wrong number or
  a broken native template.

The stricter condition therefore lost eight control-correct outcomes through
its explicit skip behavior. Reporting only its accepted subset would hide an
important practical cost. Verdict-last also lost one exact-format case by saying
`sealed, not open` instead of the required `sealed`; the strict score is not
claiming that this wording reversed the factual meaning.

Mean AMD response times were 3.910, 3.896, and 4.234 seconds for the three arms;
NVIDIA control/revision calls averaged 1.451 seconds. These exclude loading,
hashing, tokenizer/template calls, and 126.28 seconds of total AMD cooldown.
Peak AMD junction temperature was 80 C and peak whole-device VRAM 7.54 GiB.
The owned AMD runtime and endpoint were gone at closeout, and the primary Qwen
remained healthy and idle with its configuration unchanged.

**Assessment:** retain deterministic integrity checks for what they actually
establish, but do not promote either experimental protocol as a useful factual
validator. An optional, attributed critique role remains a possible product
choice; it should not become a prerequisite for the LibreChat trial on this
evidence. See [M3C](AMD_REVIEWER_M3C_REVIEW.md).

## 7. Review exposure, acceptance, and LoRA history

The intended developmental record separates:

**Recorded → Available → Encountered → Considered → Accepted or rejected.**

These are distinct events. Availability does not establish retrieval; inclusion
in model input establishes exposure, not comprehension. Consideration or
acceptance may initially be an attributed model report, not proof of durable
behavioral change. Later observed behavior must be recorded independently.

Automatic review visibility and the feedback path into ordinary Soul conversation
remain unimplemented. Experimental reviews are detached; they have not been
ingested into ordinary memory. No model is allowed to promote its own review,
note, or inferred lesson into trusted policy.

The LoRA proposal also remains prospective. Disabling an adapter would restore
the base inference configuration, not erase notes, answers, or other changes
created while it was active. A future trial should isolate all writable state
and distinguish three histories:

- Adapter active, with its resulting history.
- Adapter removed, with that history retained.
- Clean baseline, with neither the adapter nor its downstream history.

Only then could we study whether effects persist through external records after
the parameter modification is removed. We have no evidence yet that LoRA would
solve the observed calibration or instruction-following problems, nor qualified
training data or a training run.

Here, “adapter” can also mean the implemented model/protocol or LibreChat
transport code. Those software adapters are not trained weight adapters.

## 8. Relevant safeguards and validation mechanisms

The surrounding system is intended to make operational limits enforceable,
rather than asking the model to remember every safety rule.

- **Authority stays outside model output.** Effective platform limits and current
  user authorization govern the work, with repository safeguards, accepted briefs,
  and narrower role assignments beneath them. Model suggestions never grant
  permission. Irreversible deletion, private-data/credential transfer, and
  network or power changes retain their human authorization requirements.
- **Execution is bounded and foreground.** Workers and experiments have call,
  time, state, and resource limits, explicit terminal states, and cleanup. No
  idle reflective process, autonomous scheduler, or resident reviewer was added.
- **Safety is tested deterministically.** Model evaluations assess usefulness
  and behavior; they do not qualify permissions, destructive safety, persistence,
  or privilege. Validation includes input bounds, malformed/duplicate JSON,
  revision conflicts, stale results, cancellation, timeouts, uncertain state,
  scope checks, and owned-process cleanup.
- **Evidence is reproducible within its scope.** Protocols bind source fixtures,
  implementation revisions, model assets, templates, and configuration. Earlier
  failures, original mechanical scores, raw outputs, and separate semantic
  assessments are retained rather than overwritten after interpretation changes.
- **Experimental state stays separate.** No private conversational memory is
  required by these synthetic evaluations. Ordinary Soul memory and production
  defaults are not automatically updated from experimental results.
- **GPU admission protects the existing session.** The cooperative lease and
  resource checks do not evict another application or silently unload a user's
  work. They also cannot fence an arbitrary client that ignores the lease.

Several planned AMD windows were refused because Opera exceeded the existing
512 MiB foreign-allocation threshold, even when there was apparently spare VRAM.
This is a conservative workload-admission rule, not proof that the model could
not physically fit. Its desktop usability is an open tradeoff. We did not close
applications or relax that rule to obtain the latest result.

Thermal-aborted attempts were retained. Later tests used the operator-approved
90 C edge / 100 C junction / 90 C memory abort thresholds, sampled every 0.5
seconds, with bounded cooldown and resource guards. The 100 C junction limit
is a chosen test cutoff, not a claim that sustained operation there is ideal.
The operator's 2400 MHz AMD clock cap and fan settings were preserved. Matched
stock/underclock/undervolt comparisons remain deferred.

The deterministic suites were substantial but overlap across stages. For scale,
A13 recorded 713 grouped checks, A18 562, A19 259, A22 99 new plus 417 inherited,
A23 133, M1 269, and M3C 89. These counts are not additive independent tests and
are not behavioral accuracy. Their value lies in the contracts exercised.

### What the ledger cannot prove

The local journals and revision hashes support causal history, replay, and
attribution to an observed runtime configuration. They are not a publicly
anchored consensus ledger or an independent witness immune to the account that
owns the files. Local hash chains alone do not prevent that owner from rewriting
history and recomputing hashes.

They also do not identify an unexposed internal instance of a remote model,
prove subjective continuity, or show that a model experienced an event. A
process-restart comparison with the same carried record is still a separate
experiment; worker restarts and ordinary service restoration do not substitute
for it.

## 9. LibreChat readiness and the next practical gate

A22 implements a loopback, authenticated, OpenAI-compatible text-chat adapter
over the A19 practical profile, with JSON and buffered streaming responses.
It binds a private conversation root to its corpus/configuration revisions,
stores linear conversation history, rejects conflicting forks, and returns the
same committed completion for an exact retry without another model call.
It does not accept arbitrary client system prompts, attachments, or tool access.

The qualification passed six synthetic end-to-end application/gateway/worker/Qwen
turns and six exact retries with zero additional inference. Responses took
roughly 2.18–4.01 seconds. However, the qualification script exited with a
final-summary variable-scope error. A separate zero-inference reconciliation
verified the six committed replies and cleanup. This is reconciled evidence,
not an unqualified claim that the original harness exited cleanly.

Private-root initialization was hardened and the reporting defect repaired after
that live trial, with deterministic checks but no further inference. Historical
adapter roots remain bound to their original implementation revisions; the next
connection trial uses a fresh compatible root.

The installed LibreChat client serializer, configuration schema, and streaming
format were checked with fixtures. A configuration example and activation
handoff are staged. They have not been installed as the active connection, and
the actual rendered LibreChat workflow has not been accepted.

Streaming is intentionally buffered until the answer is durably journaled.
LibreChat can receive the streaming protocol, but not a live token-by-token
display during generation. That is a visible latency tradeoff for retry-safe
delivery, not a missing capability we have already tested around.

The staged client-side token budget prevents LibreChat from prematurely trimming
the transport history. It does not expand the local model beyond 4096 tokens.
The adapter still selects the bounded recent history and small complete corpus.
Conversation roots are currently limited to 16 conversations and 32 turns per
conversation. Foreground serving is bounded, with a default 1800-second lifetime
and 32 HTTP requests; these are deliberate trial limits, not an always-on chat
service contract.

The next practical gate is to activate the staged connection in a quiet window
with local credential enrollment, preservation of the existing LibreChat
configuration, and an explicit private-data retention choice. Then test:

1. Ordinary question/answer and a short natural conversation.
2. A preference or factual correction followed by a callback.
3. Reloading the UI while retaining the same conversation identity.
4. Separate conversations not leaking each other's records.
5. A disconnect after commit followed by an exact retry, without duplicate inference.
6. Conflicting history/forks being refused rather than overwriting a conversation.
7. Foreground adapter stop and resume, with no leaked worker or listener.

The older adaptation-plan headline says model-server restart is untested and
no service change occurred. That describes the state through A22, not all later
work: A23 did stop and restore the model service for comparisons. What remains
untested is **A22 conversation/journal/retry recovery across a model-server
restart**, and a controlled persistent-process-versus-restarted-process study.

Source: [A22 evidence](CONTINUITY_LAB_A22_REVIEW.md) and
[LibreChat activation handoff](../guides/CONTINUITY_LIBRECHAT_HANDOFF.md).

## 10. Outstanding issues and decisions

| Area | Outstanding issue | Present position |
| --- | --- | --- |
| Everyday usefulness | Small synthetic tests do not establish satisfying ongoing conversation | Proceed toward a bounded operator trial; define usefulness and failure observations before running it. |
| Reasoning with complete evidence | Constraint filtering, cheapest/eligible selection, and contradictory explanations still fail | Keep the explicit deterministic helper available; do not describe the issue as solved by memory. |
| Long histories and large corpora | Three recent exchanges and a small complete corpus will not cover general document work or months of conversation | Deliberate limits for the first trial; larger retrieval/context policy needs separate design and evidence. |
| Reviewer semantics | Unsupported versus contradicted and mixed judgments are poorly calibrated | No trusted-validator promotion. Optional unendorsed critique is the narrower candidate role. |
| Reviewer protocol complexity | Extra required fields can reduce usable outputs; exact quotes do not prove entailment | Preserve integrity checks but weigh rejection/skip costs and task requirements explicitly. |
| Output format | Qwen may ignore an accurate missing-unit correction | Consider deterministic rendering for genuinely typed outputs; natural-language interpretation must still be qualified. |
| Hardware sharing | Quiet-host admission and cooldown interrupt desktop work | A less conservative policy would need a fresh resource/safety contract, not only a lower threshold. |
| Process continuity | Actual service restoration occurred, but matched restart/record experiments have not | Keep operational recovery and continuity research as separate questions. |
| Developmental feedback | Review exposure, model disposition, and later behavior are not yet connected | Do not infer learning from an available review or plan training from unqualified labels. |
| LoRA | No training, qualified dataset, or isolated lineage trial | Defer until there is a specific reproducible failure and credible evaluation of benefit. |
| Production integration | No actual LibreChat UI acceptance or always-on lifecycle | Use the staged foreground connection trial before enlarging persistence or authority. |

The most defensible next step is **a narrow LibreChat usability trial with Qwen8
and the A19 practical profile**, keeping the AMD reviewer out of the critical
path. This is a proposed next step for review, not a statement that activation
or acceptance has happened.

## 11. Questions for an independent reviewer

1. **Have we changed the scientific question too far?** Are the retained minimal
   condition and explicit practical profiles enough to preserve meaningful
   comparisons, or should the project be split more clearly into a usability
   product and a separate memory/continuity experiment?
2. **What is the smallest useful next evaluation?** Which ordinary conversations
   and tasks would expose problems that these short fictional catalogs and
   seeded error cases miss, without creating another large benchmark project?
3. **Are the reviewer verdicts well specified?** We use open-world semantics:
   absence from the provided record means unsupported, not false. Could the
   instruction/schema, training conventions, or wording still encourage a
   closed-world interpretation? How would you isolate these explanations?
4. **Does the reviewer need a verdict at all?** Would attributed questions,
   counterexamples, or evidence requests be more useful than four-way labels?
   What would demonstrate benefit beyond no-review reconsideration?
5. **Did the stricter protocol help the right thing?** It improved enforceable
   citation/coverage requirements but reduced useful completion. Which fields
   belong in model output, and which can the system safely supply or validate
   without laundering an unsupported judgment into an authoritative result?
6. **Where should deterministic tools begin and end?** Can typed extraction,
   arithmetic, comparison, and rendering solve the recurring practical defects
   without hiding the still-unqualified natural-language interpretation step?
7. **Is there a worthwhile reasoning-mode experiment?** The larger-model tests
   were non-thinking, with model-specific samplers and different native templates.
   Is a bounded reasoning-enabled comparison worth its memory/latency cost, and
   what would make it fair rather than another round of prompt tuning?
8. **What should count as continuity here?** What extra result would a persistent
   process provide over a restarted process receiving the same recorded state?
   Which persistent state must be equalized before interpreting a difference?
9. **What would justify LoRA?** What failure, dataset provenance, withheld test,
   and isolated-history design would warrant parameter adaptation instead of
   changing the surrounding software or accepting a documented limitation?
10. **Where should we stop adding machinery?** Which mechanisms are essential
    for useful, recoverable operation, which belong only in research, and what
    evidence would justify declaring the practical trial good enough?

Please distinguish observations supported by this record from hypotheses and
new experiments. A useful review may recommend removing or deferring mechanisms,
not just adding more.

## Evidence map

The linked assessments contain exact commands, frozen configurations, per-case
discussion, development checks, retained failures, and local evidence locations.
This map is for follow-up inspection; raw directories should not be uploaded
wholesale because some contain local ephemeral credential material.

- Plan and approvals: `docs/soul/CONTINUITY_LAB_ADAPTATION_PLAN.md` and individual
  `CONTINUITY_LAB_A*_BRIEF.md` files.
- Context and usability: `docs/assessments/CONTINUITY_LAB_A13_REVIEW.md` through
  `CONTINUITY_LAB_A20_REVIEW.md`.
- Verified helper: `docs/assessments/CONTINUITY_LAB_A21_REVIEW.md` and
  `scripts/continuity-lab-select.rb`.
- Conversation adapter: `docs/assessments/CONTINUITY_LAB_A22_REVIEW.md`,
  `docs/guides/CONTINUITY_LIBRECHAT_HANDOFF.md`, and
  `scripts/continuity-lab-chat.rb`.
- Larger models: `docs/assessments/CONTINUITY_LAB_A23_REVIEW.md` and its two
  retained comparison evidence roots.
- Detached reviewer contract: `docs/soul/AMD_REVIEWER_M0_M1_BRIEF.md` and
  `docs/assessments/AMD_REVIEWER_M0_M1_REVIEW.md`.
- Reviewer operation and quality: `docs/assessments/AMD_REVIEWER_M2_REVIEW.md`,
  `AMD_REVIEWER_M3_REVIEW.md`, `AMD_REVIEWER_M3B_REVIEW.md`, and
  `AMD_REVIEWER_M3C_REVIEW.md`.
- Runtime implementation: `lib/soul_core/continuity_lab/` and
  `lib/soul_core/reviewer/`, with bounded experiment and verifier scripts under
  `scripts/`.
- Promotion/evidence policy: `AGENTS.md`, `docs/soul/HUMAN_REVIEW_GATE.md`,
  `skills/_template/REVIEW.md`, and `docs/soul/CLOUD_LLM_POLICY.md`.

All reported stages separate source inspection, deterministic checks, actual
runtime behavior, model-answer quality, and human acceptance. Passing one level
does not silently establish the others.
