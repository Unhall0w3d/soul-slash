# Continuity A25: capability, elicitation, and protocol comparison

Date: 2026-10-13. The current user explicitly requests designing and performing
this bounded experiment after the A24 LibreChat usability trial. This brief
records that authorization; it does not adopt a new model or change Soul's
working configuration. A25 is the Continuity sequence, unrelated to the older
Memory Projection A25 milestone.

## Question and candidate

Distinguish failure from unavailable evidence, output/protocol restrictions,
inadequate deliberation, and remaining model-configuration limitations. Do not
claim to isolate innate capability or parameter count from these small tests.

Use resident NVIDIA Qwen3-8B Q4_K_M and the cached, pinned AMD Qwen3.5-9B Q4_K_M.
The AMD choice has verified full-GPU fit and native thinking branches, with
lower cost/heat than the previously tested 14B reviewers. It is only 9B versus
8B, not a large parameter scale-up; any advantage belongs to the tested model
configuration/family, not demonstrated size causation. No new weights/downloads,
service or Core changes, LoRA, memory ingestion, or silent fallback.

## Frozen design before scored inference

- Six fresh tasks: easy/hard pairs for constraint filtering and cost comparison,
  multi-step arithmetic with explicit units/time, and evidence joins with
  revision/unknown handling. Use synthetic sources, new content and independent
  deterministic oracles. No prior A19–A23/M3 fixtures or seeded source answers.
- Fully crossed: two models × native thinking off/on × strict final-answer JSON
  versus relaxed prose × six tasks × three independent seeds = 144 first calls.
- Give each initial answer one source-only self-reconsideration, without external
  reviewer feedback or correctness hints: another 144 calls. Only that initial
  answer enters its own reconsideration. Every other cell starts fresh; disable
  prompt-cache reuse. Counterbalance model/condition order by case/seed.
- Same evidence, question, and final-answer fields across conditions. Public
  payloads exclude expected answers, oracle data, difficulty/family labels, and
  scoring instructions that disclose outcomes. Retain exact rendered prompts.
- The strict contract constrains the final answer, not the native reasoning
  segment. First verify native on/off rendering and final-answer grammar routing
  with unrelated unscored fixtures. If installed backends cannot support that
  distinction, report the incompatibility; do not score a deliberately broken
  thinking/grammar combination as a capability failure.
- Each ordinary call allows 768 newly generated tokens, including reasoning,
  and 45 seconds of completion-request time. Separate first/reconsidered results,
  including exhausted, invalid, and missing final answers. Do not require equal
  output lengths or describe unused allowances as consumed compute.
- Equalized-budget contrast: for the three hard tasks and each seed/model, add
  one relaxed, thinking-enabled direct call with 1536 generated tokens/90 seconds
  and compare it to the relaxed, thinking-off first+reconsideration pair capped
  at 2×768 tokens and 2×45 seconds. This adds 18 calls, for 306 scored calls.
  Both have the same aggregate output-token and completion-time allowances; record
  actual tokenization/input/output counts and latency. Retain separate reasoning
  token counts only if the backend provides them; otherwise mark unavailable
  and retain reasoning character counts as characters, not token estimates. Native tokens
  differ and FLOPs are not measured: this equalizes practical inference budgets,
  not literal arithmetic work across architectures or unused elapsed time.
- Use three preregistered seeds (104729, 130363, 155921), shared sampler settings
  matching the existing Qwen8 baseline unless a zero-generation compatibility
  check proves unsupported: temperature 0.6, top-p 0.95, top-k 20, min-p 0,
  presence penalty 0.5, repeat penalty 1.05, no LoRA, no prompt caching. Record
  actual effective settings; any justified compatibility revision is frozen
  before scored cases, not made after outcomes.
- Keep the installed 4096 context. Reserve 1536 input tokens for all conditions
  so the longest 1536-token output fits; refuse oversized essential evidence
  rather than truncate. Reconsideration uses only the final answer, never prior
  reasoning; bound it before any model call and retain overflow as a skipped
  prerequisite, not an invented answer.

## Bounds, preservation, and gates

At most eight unrelated feasibility generations before scoring and 306 scored
calls. Execute three independently bounded seed windows (102 scored calls each,
at most 3600 seconds per window), ending and reaping the AMD child between them.
No automatic retry of uncertain inference or silent continuation after a guard
failure. A failed window is retained; diagnose safely before a separately recorded
repair/window. No scored-case tuning or cherry-picked reruns.

Reuse the reviewed shared GPU lease/control lock, exact model/runtime attestation,
quiet-host admission, 1 GiB foreign-allocation cutoff, 90/100/90 C edge/junction/
memory abort limits, 0.5-second samples, minimum three-second AMD cooldown,
RAM/VRAM/swap guards, and owned-process cleanup. No LACT/sysfs tuning or application
termination. A cooperative gate is not an OS-wide reservation.

Primary owns execution, safety, persistence, experimental conclusions, and final
read-back. Delegated workers may own fresh fixtures or detached pure protocol
code with named paths. Preserve all dirty work, original profiles, previous
evidence, model/Core/configuration hashes, and unresolved failure receipts.

Runtime executable/library hashes and preservation snapshots must match across
all seed windows, not just within each. Retain the actual native response prompt
alongside the preview used for token admission. Feasibility proves the eight
simple native combinations and records effective grammar; it does not establish
that grammar routing is correct for every possible answer. The strict/prose
contrast tests this bounded answer contract, not all of Soul's retrieval,
reviewer-envelope, or conversational protocol constraints.

## Scoring and interpretation

Before inference, validate fixture oracles and public/oracle separation. Test
protocol parsing, reasoning/final separation, strict and relaxed final extraction,
call/time/token bounds, source binding, independent sample/reconsideration
pairing, and resource/cancellation/cleanup behavior using deterministic fixtures.
Never use model judgments to qualify safety or authority.

Score semantic correctness separately from strict-contract compliance. Strict
structured answers get deterministic field/value checks; free text receives
identity-masked full-answer semantic assessment against the same frozen oracle,
with ambiguous/contradictory answers not passed on keyword matches. Retain raw
mechanical results, output limits, skipped prerequisites and assessments.

Report paired first/reconsideration wins and regressions; on/off and contract
contrasts within each task; performance by difficulty; latency and actual input/
output tokens; equal-budget direct-deliberation versus reconsideration results.
A reproducible per-task model advantage requires candidate correctness on all
three independent samples and baseline correctness on at most one, under the
same condition/budget, without trading away contract validity. Report every
task, not only those meeting this exploratory threshold. It is not statistical
proof of broad superiority; six tasks and three seeds remain a pilot.

If relaxed outputs fix errors, discuss protocol sensitivity; if deliberation
fixes them, discuss elicitation/budget sensitivity. Persistent errors under all
tested conditions indicate a remaining practical limitation, not proof that the
weights lack the capability. Identify interactions and inconclusive cases.
No automatic promotion, reviewer dependency, training, or new production model.
