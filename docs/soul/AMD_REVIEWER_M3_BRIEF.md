# Optional AMD reviewer — M3 bounded quality comparison

2026-10-13. The operator's “please proceed” authorizes the M3 comparison proposed
in the M2 assessment. This is a foreground qualification, not production delivery
or approval of M4, LoRA, memory promotion, LibreChat changes or a new service.

## Question and frozen comparison

Does cached Ministral14 on AMD improve Qwen8's answers more than Qwen self-review,
and does deriving an independent answer before seeing Qwen's answer help?

Ten fresh, synthetic, self-contained cases cover revision selection, joins,
arithmetic, filtered selection and absent evidence. Freeze cases, oracles,
prompts, scoring and source hashes before inference. Oracles and seeded answers
never enter ordinary answer/review requests. No private data or live task is used.

For each case, make one Qwen answer and fork three independent branches:

1. **Self-review:** Qwen reviews its exact answer in a fresh request, then Qwen
   revises it using that review. This reconstructs context; it does not preserve
   hidden state or claim process continuity.
2. **AMD direct review:** Ministral reviews that same original answer; Qwen
   revises from the original plus that review.
3. **AMD evidence-first:** Ministral independently answers from only the question
   and evidence, then reviews Qwen's original with its independent answer visible
   as an untrusted comparison. Qwen revises from the original plus that review.

Rotate the three branch orders by case index; no branch consumes another branch's
revision. Independent evidence-first derivation never receives the source answer.
Additionally, both models review one authored seed per case: five supported,
three contradicted, two unsupported. These audits measure verdict calibration,
not genuine self-review or naturally occurring primary errors.

The maximum is 100 generations (10 per case). Both models use native templates,
4096 context, <=3072 input tokens, 768 output tokens, seed 4242, temperature .05,
top-p 1, top-k 0, min-p 0, repeat penalty 1, prompt caching off. Qwen thinking is
explicitly disabled. This tests these configurations, not architecture in
isolation or superiority under every sampler. Grammar constrains shape, not truth.

## Scoring and interpretation

Answers are closed maps of one to three short strings. Prompts disclose the
expected units/format and literal `unknown`, never the expected values. Exact
field matching allows surrounding whitespace and letter-case normalization only.
Report format-equivalent misses separately; never silently rescore them. Report
whole-answer and field scores, corrected wrong answers, spoiled correct answers,
net corrections, paired differences, latency and call cost. Partial/harness
failures are not valid reviews and are not retried automatically.

Review verdict definitions are explicit for both models: supported means no
unsupported/false claim; contradicted requires positive contrary evidence;
insufficient_evidence means unsupported definite claims without contrary
evidence; mixed means both contradiction and unsupported claims. A correct
`unknown` is not an unsupported definite claim. Schema-valid citation IDs do not
prove that a finding is grounded; inspect findings qualitatively as well.

Any recommendation to advance beyond qualification needs a net positive paired
effect without spoiled correct answers or spurious criticism in the supported
seed reviews. Seeds receive reviews only: their false verdicts/recommendations
are not measured applied corrections. A ceiling result or too few natural errors
is inconclusive, not a pass.
No significance/population reliability claim is possible from ten synthetic cases.
Record historical M2's unsupported/contradicted error unchanged. M3's explicit
definitions are a declared common prompt adjustment, not retrospective repair.

## Runtime and authority

Primary owns `scripts/compare-amd-reviewer-m3.rb`, runtime/authority decisions,
this brief and assessment. Luna may own only the fresh case/scorer helper and
targeted deterministic tests; Sol may critique read-only. Preserve the dirty tree.
Do not edit fingerprinted M1/Continuity source or existing M2 helpers.

Reuse M2's installed Vulkan runtime, cached publisher-pinned Ministral14, private
API key, fixed loopback endpoint 8096, full offload attestation, resource guard,
owned-child cleanup and exclusive AMD lease. No installs/downloads or model swap.
Leave NVIDIA Qwen resident on 8082. Hold the existing model-runtime control lock
during inference, admitting only this process's AMD lease; check exact Qwen
service/PID/template/Core and idle slot. This blocks cooperating Soul requests
but cannot exclude arbitrary direct clients or games; busy means stop, not evict.

One window <=1800 seconds, each Qwen generation <=60 seconds, AMD <=90 seconds,
startup <=180 seconds. Preserve M2 thermal/headroom/swap/log bounds. Always close
and reap the owned AMD child. After an interrupted Qwen request, wait at most
15 seconds for its slot to become idle; do not kill/restart Qwen. If unconfirmed,
retain the lease for inspection and explicitly report the unresolved request.
No automatic rerun, service, scheduler, background completion or M1 store write.
Retain isolated private requests, responses, source/evidence/protocol/runtime
revisions and failed attempts under `Soul/runtime/qualification`.

## Required evidence

Before live inference: syntax, case/scorer tests, runner boundary tests, inherited
M2 lifecycle tests, changed-path required checks and focused review. Tests cover
oracle isolation, independent branches, evidence-first blindness, revision binding,
strict completion/budgets, busy admission, quiescence and retained-lease failure.
After: compare source/config/service/runtime hashes and Qwen PID, confirm idle
slot, closed 8096, reaped AMD child, released VRAM and no owned lease. Update the
assessment and canonical review indexes. Deterministic, live, semantic and human
approval evidence remain separate. Do not advance to production automatically.

## Retained thermal abort and lower-load revision

The first attempt stopped on generation seven, before any complete case. Its
2-second sample reached edge 84 C / junction 99 C, versus the unchanged 80/95 C
cutoffs; the preceding sample was 45/58 C. Six responses, partial seventh stream,
all samples and original runner/brief are retained. No quality score is promoted.
Teardown and identity/lease read-back passed. This is a resource abort, not an
inference-format failure; the actual AMD SSE framing passed the strict parser.

One explicitly initiated lower-load attempt is within this bounded evaluation:
reduce only the temporary AMD runtime batch/microbatch from 512/128 to 128/32,
and require at least three seconds idle before every AMD generation, resuming
only at edge <=55 C and junction <=70 C within 30 seconds. Keep the 80/95 C abort
thresholds, same models, cases, prompts, sampler, scoring and 1800-second window.
Do not touch LACT, power/clock/fan controls, drivers or production services. Stop
if the revised window again exceeds a resource bound; no automatic retry loop.
This creates protocol v2 and a separate evidence root. Case one's initial outputs
have been observed; this is a declared repeat, not ten wholly unseen cases. Do
not pool the aborted run with the complete comparison, or credit prompt tuning
for a resource-only adjustment. Include cooldown time in operational cost.
