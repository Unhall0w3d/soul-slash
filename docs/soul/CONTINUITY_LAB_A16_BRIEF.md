# Continuity A16: retrieval-guidance-only comparison

## Authority and outcome

The owner approved the proposed A16 scope with "okay, i agree let's proceed".
Implement an opt-in retrieval-guidance change, run deterministic checks, and
perform one bounded comparison on the existing idle Qwen runtime if its exact
identity and admission checks pass. Primary owns admission, live execution,
evidence interpretation and the review. This is not approval for a new model,
server restart, automatic context expansion, ordinary memory, deployment,
background activity or release. Preserve dirty work and all previous evidence.

Question: does explicitly explaining the existing retrieval interface improve
ordinary task and conversation callbacks, without changing matching or context?
This is a small paired pilot, not a population reliability estimate.

## Frozen intervention and cases

Baseline: unchanged A13 receipt-pairs projection, A15 task/case/scorer behavior,
Qwen3-8B-Q4_K_M, llama.cpp b9851, sampler, grammar, 3072 input-token budget,
one inference slot, current-event receipts and new worker per event.
Candidate: append one versioned host-owned retrieval guide to the system
message before normal template rendering and actual-token measurement. Explain
collections, exact-word AND matching, shorter queries after empty results,
discovering IDs/revisions from hits, and retrieving missing history. Add no
expected answers, example facts from cases, synthetic memory or new capabilities.

Use an A16-only transport adapter so all existing A0-A15 source files and default
behavior remain byte-identical. Both conditions use the same adapter path;
baseline leaves the template payload unchanged. Capture the condition, guide
text/digest, code hashes and actual prompt/token receipts. Reject candidate
injection unless the system message exactly matches the frozen receipt-pairs
composition. No endpoint, transport permission or worker protocol is broadened.

Reuse all twelve A15 requests unchanged in planning, holdout and conversation
batches. Add one four-event held-out transfer batch covering source lookup,
changed decision, callback and a genuinely absent fact. Freeze cases and scorer
before live outputs. Each condition starts an independent empty store with the
same corpus; only within-batch history carries forward. Order alternates:
planning baseline/guided; holdout guided/baseline; conversation baseline/guided;
transfer guided/baseline. Different histories caused by earlier responses are
part of the multi-turn intervention; this is not identical-input next-token testing.

## Bounds and failure behavior

One suite, eight batches / thirty-two events maximum. At most six generations
per event, twenty-four per batch and 192 total; at most 1800 seconds total,
including a twenty-second final cleanup reserve. Existing 60-second stream,
420-second event and 430-second worker limits remain. No case retries, prompt
retuning, or scorer changes after seeing live results. Stop on infrastructure
failure, ambiguous intent, blocked-for-review state or input-budget failure;
record remaining cases as unstarted. Behavioral failures remain results and do
not by themselves authorize a repair/rerun. Verify worker exit and idle inference.
Execution deadline, unavailable fixture/backend and unknown terminal reasons
stop the suite. Repeated failed actions, invalid-action exhaustion and model/tool
call-budget exhaustion remain behavioral outcomes; these do not trigger retries.
No job survives the foreground turn. Busy or incompatible runtime means preserve
the candidate and report the live gate, not evict other work or switch models.

## Acceptance and interpretation

Deterministic checks must establish baseline payload identity, candidate-only
system-message addition, unchanged data messages and sampler, actual modified
prompt tokenization, receipt provenance, rejection of wrong projection/profile,
unchanged historical code hashes, held-out positive/negative fixtures, and an
actual isolated worker using the adapter and existing admission/receipt path.
Retain old mechanical screening unchanged; report its known phrase-matching
limitations separately from primary semantic assessment. Synthetic tests are
not live model qualification and model judgments never establish safety.

Record per-case correct/incorrect/partial outcomes, observed supporting sources,
tool failures, guessed IDs, unnecessary operator repair, note behavior, calls,
input/output tokens, timing and omissions. Independently check actual tool
effects through existing replay. Primary reviews raw replies and traces, with
the fixed expected facts outside model inputs. Do not combine semantic-only
greetings with factual tasks into a misleading overall pass rate. A candidate
usefulness result requires grounded retrieval, correct changed-decision recall,
appropriate unknown handling and conversational callback without manual hints;
report any regression on no-tool and previously adequate cases. Partial gains
do not qualify everyday usability or restart equivalence.

## Owned additions and checks

Add `retrieval_guidance_a16.rb`, `qualification_cases_a16.rb`, an A16 runner,
guidance/case verifiers, this brief and its review. Update only the adaptation
plan and canonical review links after validation. No historical runtime files,
trials, briefs, scores or reviews are rewritten.

Use pinned Ruby 4.0.7. Run syntax checks on new Ruby files, the new verifiers,
`verify-continuity-lab-usability-a15.rb`, and one actual-isolation adapter check.
Reuse historical unchanged runtime checks instead of repeating the entire lab.
Validate historical stores and compare their pre/post content hashes without
resuming them. The final review distinguishes implementation, deterministic
checks, live results and owner acceptance. Search-matching repair, recent-dialogue
context and model-server restart remain separate later decisions/experiments.
