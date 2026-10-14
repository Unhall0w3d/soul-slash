# Continuity Lab A6 visible-history comparison

Owner authorization: "please continue" after the A5 review proposed a controlled
comparison of smaller reads with all results visible versus context omission.
This authorizes the fixture/harness, deterministic checks, tokenizer-only sizing
and one fresh four-case live window. It does not authorize a runtime repair,
progress-summary/receipt interface, another model batch, dashboard wiring,
ordinary-memory activation, service/model changes, merge or release.

## Comparison and ownership

Primary owns architecture, live host access, synthetic stores and evidence.
Luna provides read-only contract mapping. Add a separate A6 case catalog,
qualification harness and verifier; retain A0-A5 source/profiles/results unchanged.

Two pairs use the same corpus and request within each pair: four successive
768-character reads then the final marker; and three successive reads followed
by a re-read of the first span then its marker. Marker placement preserves the
four-step task, not the original 1024-character corpus bytes. The second request
does not assert that omission occurred: that is host-measured evidence, not an
instructional difference between arms. Use the existing v4 normal and rollover
profiles (3072 versus 2048 actual input tokens). Reverse arm order for the second
pair. Fresh independent stores/workers have different random lineage IDs; record
that nuisance variable and do not claim a randomized or replicated causal result.

Keep model/build/template, guide, grammar, sampler, six-call ceiling, resident 4K,
768 output reserve and 256 margin unchanged. No forced action, model-side progress
summary, answer injection or relaxed successful-tool sequence scoring.

Before generation, measure expected envelopes at each of the five intended
decision points using the installed formatter/tokenizer and each actual store's
lineage. Require the intended five-call path to fit 3072, and group 0 to be omitted
by the fourth call under 2048 for the reread pair (by the fifth call for four
reads). Fail before inference if sizing does not establish the intended contrast.
These expected traces are explicitly deterministic fixtures, not model output;
they never enter live journals. Measure actual omissions separately from task
success, including early exits or deviations that fail to exercise a condition.
Beyond the planned five calls, a failed visible-arm sequence may itself exhaust
context; retain this rather than calling it an all-visible test.

## Acceptance and bounds

- New A6 verifier: identical paired tasks/corpus/contracts, valid marker spans,
  strict expected sequence/reply, extra/reordered/skipped reads rejected,
  omission evidence distinguished from task success and missing evidence.
- Reuse unchanged A5 runtime/isolation evidence; run A4 scoring, A5 token-context
  regressions and Ruby syntax checks for the new files.
- One foreground window, four cases, at most 24 generations, six per case,
  480 seconds total, 60 per worker, 30 per HTTP request. Tokenizer-only sizing
  shares the overall deadline. Stop for drift, busy admission, infrastructure
  failure or an ungrounded/blocked event; no silent tuning or retry.
- Supported exact host escalation, admission/idle and identity checks before,
  between and after cases; cooperative admission cannot exclude outside clients.
- New private Git-ignored `Soul/runtime/qualification/continuity-lab-a6-*` root;
  retain baseline, sizing fixtures, raw prompts/tokens/results, journals and
  scored outcomes. Reap all workers and independently verify idle at completion.
- Update review packet, adaptation plan and canonical review links. A completed
  comparison is not broader continuity acceptance or permission for promotion.

## Executed window

One window ran October 8, ending 14:40:24 EDT. Expected-path tokenizer calibration
passed for all four cases. The first case returned three correct reads, then its
fourth generation exceeded the 30-second HTTP limit while all prior results
were visible. One case is interrupted/unscored, three unstarted. The service
subsequently returned idle; unresolved intent is retained without regeneration.
See [A6 review](../assessments/CONTINUITY_LAB_A6_REVIEW.md). No automatic retry.
