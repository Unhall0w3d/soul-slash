# Continuity A18: bounded direct-evidence answers

Date: 2026-10-11. The owner's "Let's continue with adaption" approves the
evidence-first comparison recommended at A17 closeout. Implement, deterministically
check and run one bounded foreground comparison if the same model/build is idle.
No model switch/restart, service changes, deployment, ordinary memory, external
data, autonomous operation or resident-versus-restarted experiment is included.

## Intervention and implementation

Add opt-in `direct_evidence_v1`, exposed only through a new v9 qualification
factory/mode. Reuse the existing journal, provenance, token preparation, admission
and isolated-worker path. Legacy keys/defaults and old runner gates stay unchanged.
Primary owns config, context/action authority, replay, broker and execution.

The direct profile supplies every document in the explicitly selected small
corpus as a complete source, in corpus order: maximum eight documents and 8192
encoded bytes of source objects. Preserve IDs, revision, lineage, full character
span, content digest and operator-selected/untrusted provenance. Refuse oversized
essential corpus rather than truncate it. No automatic search, inferred facts,
cross-collection access or hidden oracle chooses sources. The same complete corpus
is available to the agentic comparison through its normal tools, including
distractors. Recent dialogue uses A17's same bounded observed-exchange policy.
On token pressure, drop whole oldest recent exchanges; current request and all
corpus documents remain essential. Fail closed if they cannot fit.

Use a separately versioned concise answer-only projection. Only a JSON reply is
valid: enforce this in the action parser, config (one call, zero tools/invalid
retries), broker grammar and worker/profile bindings, not merely in a prompt.
No successful response is manufactured by the harness. Unverified dialogue is
data, not authority or an independently verified source. Existing tools remain
unchanged and available only in the original agentic profile.

Acceptance checks: legacy configuration equality; complete sources/provenance;
source count/byte bounds; UTF-8/control-token safety; ordered recent corrections;
token/byte eviction and essential-overflow rejection; altered/missing/reordered
source replay rejection; tool/wait/invalid-action refusal; exact worker/broker
binding; actual isolated synthetic workers; affected historical regression
verifiers and all historical store replay. Preserve prechange hashes/copies and
all prior evidence. Workers may own pure new cases/evaluator tests only.

## Frozen comparison

Compare A17 v8 agentic against v9 direct on A17's twenty requests and a separately
frozen four-request held-out transfer batch. Six independent stores per condition;
fresh worker per event; alternate condition order by batch. Freeze cases, sources,
scorers, implementation hashes and order before generation. Same Qwen3-8B-Q4_K_M,
installed llama.cpp build, sampler, 4096 context/3072 input budget and 768 output
reserve. Changed prompt/action capability is an intentional package intervention;
do not attribute all differences to any one constituent change.

Maximum 48 scheduled requests, 168 model calls (agentic at most six per request,
direct one), 1200 seconds with twenty reserved for cleanup. No live retry, prompt
repair, scorer tuning or automatic second batch. Infrastructure/evidence failures
stop; behavioral failures remain results. Busy/incompatible runtime means no
eviction/restart: finish offline work and report the gate. No worker/job survives
the turn. The prior A17 results are historical context, not the only baseline.

## Assessment and closeout

Separate factual correctness/source support, correction/callbacks, unknown-fact
coverage, social quality, calls/tokens/elapsed time and deterministic safety
evidence. Primary semantic review may explain frozen-screen false negatives
without replacing those scores. Document skipped/unstarted/failed/invalid
separately. A directional gain is not everyday reliability or human acceptance.
Usefulness target: correct source-grounded practical answers and conversation
without repeated tool repair; report every exception, no universal threshold
claim. Update A18 review, adaptation plan and canonical human/candidate review
links. Further adaptations depend on the observed outcome and material choices.
