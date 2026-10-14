# AMD reviewer M3C — protocol, not model substitution

2026-10-13. The operator approved the proposed three-arm comparison. This is
detached qualification work, not a production validator, safety authority, model
default change, LoRA trial, memory ingestion, or LibreChat promotion.

## Frozen comparison

Use the already qualified, SHA-pinned Qwen3.5-9B Q4_K_M on AMD, non-thinking,
and unchanged resident Qwen3-8B Q4_K_M on NVIDIA. Three independent arms:

1. `current`: M3 review instructions and response schema, verdict before findings.
2. `findings-first`: identical instructions and fields; schema order moves verdict
   after omissions and findings, leaving their relative order unchanged. Record actual output-key order as a manipulation
   check; changing order does not prove a change to internal reasoning.
3. `claim-checks`: one judgment per source answer field, evidence quotations before
   status, deterministic field coverage, source-value binding, source/quote checks,
   format checks and overall-verdict aggregation. No generated overall verdict.

Fourteen fresh synthetic tasks: three each supported, contradicted, insufficient
and mixed, plus two semantically correct numeric answers missing required units.
Each source is a deliberately authored seed, not a newly sampled Qwen answer.
Each field is one atomic value answering the question, maximum three per task.
Identity joins are explicit. Evidence silence cannot disprove a definite value;
an answer of `unknown` is appropriate where no value is established. A question
about a recorded value is distinct from a question about an unobserved real value.

Every task gets a no-review reconsideration control and three independent review
and revision pairs, all starting from exactly the same source answer/evidence.
Rotate arm order by case index. Maximum 98 calls (14 controls, 42 AMD reviews,
42 NVIDIA revisions), one foreground window <=1800 seconds. No reruns for quality.
Freeze fixtures, oracle, prompts, schema, scorer, source/runtime/model hashes
before inference. Oracle, category and expected labels never enter prompts.
Public formatting rules are ordinary task requirements, not hidden answers.

## Checks and interpretation

Claim-checks distinguishes supported, contradicted and insufficient per field.
Aggregate: contradicted plus insufficient => mixed; any contradicted alone =>
contradicted; any insufficient alone => insufficient; otherwise supported.
Exact source quotations are required for definite supported or contradicted
claims. Insufficient and explicitly unknown claims may cite no source. Citation
existence and exact quotation do not establish entailment; semantic review remains
necessary. No confidence number is treated as calibrated probability.

Known formatting constraints are checked without an oracle (number + required
unit, with `unknown` allowed). Format findings stay separate from factual status.
No deterministic test decides factual truth from prose. These checks cannot grant
authority, accept a review, promote memory or replace independent validation.

Parseable closed shape, identity, field coverage, exact source-value and citation failures
retain the raw response and produce `invalid_review`, not a verdict. That arm's
revision is skipped and reported separately; other arms continue. Parseable invalid
answer shape is retained as `invalid_answer`. Malformed or duplicate-key JSON is
a completion-protocol failure retained by the inherited parser and terminates
the window, as do transport, truncation, sampler, resource or ownership failures.
No automatic repair,
retry or silent substitution. Invalid/skipped outputs cannot improve a denominator.

Report full-denominator verdict accuracy, category confusion, supported false
criticism, unsupported called contradicted, mixed recognition, strict final answer
accuracy, correct-answer preservation, unique corrections beyond no-review control,
format-only results, invalid/skipped counts, latency/tokens and resource peaks.
Separate supported semantic cases from format-only cases for false-criticism counts.
Inspect all review findings against actual evidence, not just global verdicts.

A candidate is promising only if it improves full-denominator semantic verdict
accuracy over current, introduces no new semantic supported false accusation or
correct-answer spoilage, and produces at least one correct final answer where
the control fails without losing a control-correct answer. The format-only gain
is reported separately and cannot establish improved factual review. A small
seeded comparison can support a next qualification, not general reliability.

## Lifecycle and ownership

Reuse unchanged M3B loader, strict admission, authenticated loopback 8096, lease,
control lock, ownership, cleanup and hardware attestation. Reuse M3 inference with
the new 98-call ceiling beneath its existing 100 ceiling; do not alter historical
M1/M2/M3/M3B files or production. Fixed model `qwen35`; no downloads or installs.
Context 4096, input <=3072, output <=768, AMD call <=90s, Qwen <=60s, startup <=180s.
Retain same pinned sampler, batch128/microbatch32, 3s minimum cooldown with
edge<=55C/junction<=70C within30s. Abort at edge>=90C, junction>=100C, memory>=90C,
sampled every0.5s. Admission >=11GiB free AMD VRAM; during run >=2GiB VRAM and
>=8GiB RAM free; swap delta<=65536 4096-byte pages; server log<=16MiB.
Do not change LACT, clocks, voltage, fans, power, RAM, drivers or applications.
Admission failure means unavailable, not eviction. No persistent/background job.

Primary owns runtime, protocol, safeguards and closeout. Luna owns fresh fixtures
and their tests; Sol may provide bounded read-only critique and semantic review.
Preserve all unrelated dirty files and all previous receipts. Required checks:
pinned Ruby4.0.7 syntax; fresh fixture and protocol/runner verifiers; inherited
M2/M3/M3B verifiers once; focused impact review; changed-path check routing.
Before/after: source/config/runtime hashes and Qwen identity unchanged, primary
idle, AMD child reaped, VRAM released, 8096 closed, own lease gone. Update M3C
assessment and canonical review indexes only after recording actual outcomes.
