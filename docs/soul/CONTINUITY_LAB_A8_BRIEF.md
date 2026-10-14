# Continuity Lab A8 meaningful-passage comparison

Owner authorization: "please proceed" after A7 proposed a small diagnostic
replacing repeated-letter filler with meaningful passages, retaining the model,
prompt, sampling and memory behavior. Primary owns scope and live execution.

## Scope and invariant controls

Create a separate versioned synthetic corpus and four-case catalog for the same
A6/A7 tasks: four ordered 768-character reads and a required re-read followed
by the exact marker reply. Keep IDs, offsets, request text, case order, marker
locations and strict scoring semantics unchanged. Within each pair, the request,
corpus and full contract are identical; only the existing 3072/2048 input budget
differs. Use fictional technical/narrative passages, not private source data,
instructions to the model, answers injected into prompts or forced next actions.
Short whitespace padding may align complete sentences to fixed span boundaries;
do not replace repeated-letter filler with repeated prose.

Retain A7's v5 streaming execution profile, installed Qwen/model/build/template,
guide, grammar, sampling, six calls, 768 output tokens, 256 margin, 4K resident
context and all runtime/worker/store/admission/transport implementations unchanged.
Old source files and stores remain intact. This is corpus-style diagnosis, not
a runtime repair or a claim that different prose has identical tokenization.

Before generation, measure the installed tokenizer on expected action/result
prefixes. Allow at most four non-generative fixture-sizing revisions, bounded
to ten minutes total, with no model completion calls. Freeze the first candidate
that establishes full visible histories and omission at the existing decision
boundaries with at least 64 tokens of margin on the intended side of the budget.
This margin avoids relying on a near-threshold random lineage ID; the first
sizing pass exposed such a boundary, before any generation. Retain counts and
candidate hash. The live harness repeats calibration
with each fresh store's actual lineage ID; if contrast fails, stop before any
generation rather than silently shrinking a budget or replacing a task.

One fresh live batch: four cases, at most 24 generations, 1800 seconds overall
(1780 work plus 20 cleanup reserve), with A7's 60/420/430 second request/event/
worker bounds. Stop on infrastructure failure; record behavioral failures and
continue the remaining predefined cases. No tuning or second batch afterward.
Use private Git-ignored `Soul/runtime/qualification/continuity-lab-a8-*` evidence.
No historical resume, service/GPU change, dashboard/ordinary-memory activation,
cloud, scheduler, package installation, merge or release.

## Deliverables and acceptance

- New `qualification_cases_a8.rb`, `verify-continuity-lab-comparison-a8.rb`,
  `qualify-continuity-lab-qwen-a8.rb`; A8 review and canonical review/plan updates.
- Reuse A6 expected-prefix and observed-condition logic where possible without
  editing historical implementations. Tests prove same requests and action
  contracts versus A7, genuine changed corpus, exact span/marker grounding,
  visible/rollover symmetry, and strict rejection of wrong/omitted/reordered/
  extra actions, wrong replies, missing manifests and premature completion.
- Run A8 comparison tests plus existing A6 comparison, A4 scoring and A5 token
  context checks; syntax and document consistency. Reuse A7's 656 checks only
  after matching unchanged runtime/source hashes, not as fresh A8 test results.
- Record source hashes, settings, calibrated and actual condition evidence,
  streams, final outcomes, and sampling limitations. Independently validate
  journals, unchanged historical evidence, final idle identity and worker reap.
- Distinguish task success, observed history condition, transport completion and
  human acceptance. No assertion of causal proof from a single unreplicated pair
  or equivalent token counts across corpora and random lineage identifiers.
