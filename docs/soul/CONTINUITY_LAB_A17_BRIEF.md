# Continuity A17: ranked retrieval and separately selectable recent dialogue

Date: 2026-10-11. The owner approved continuation of the A16 recommendation.
Implement and check deterministic retrieval repair, then separately selectable
recent-dialogue context, and one bounded three-condition foreground comparison
if the existing exact Qwen model/build is available and idle. This scope does not
authorize a service restart, model change, ordinary memory, release/deployment,
unattended continuation, credentials, or model-server restart experiments.

## Independent interventions

1. Persist an optional `ranked_lexical_v2` retrieval policy in new stores only.
   Absent policy retains legacy exact-word AND results and configuration digests.
   Preserve full exact matches and their order. Only if none exist, remove a
   fixed common-word list, normalize conservative English plural forms, and rank
   partial lexical candidates deterministically. Require two distinct matched
   terms when a query has multiple meaningful terms, otherwise one. Weight
   rarer terms by document frequency; tie-break by matched count then source ID.
   Return explicit matched/missing terms and coverage, never a claim of truth.
   Preserve lineage checks, source identity/revision/digest/provenance, exact
   original character spans, result quotas and read semantics. No embeddings,
   fuzzy substrings, automatic external data, cross-collection search or ID repair.
2. Persist `recent_dialogue_v1` independently from that retrieval policy. Include
   up to three completed earlier exchanges as observed, unverified dialogue,
   with source identity, digest and revision. Initial maximum 4096 encoded bytes;
   discard oldest complete exchanges first rather than truncating them. Actual
   tokenizer accounting remains authoritative. Under input pressure, omit oldest
   recent exchanges first, then use the existing tool-receipt omission policy.
   Current request and latest tool result remain essential. Replay reconstructs
   all inclusions and omissions from the journal; no fabricated summary, private
   notebook or conversion of prior assistant text into verified facts/authority.

New qualification factories/modes are opt-in. Legacy defaults, profile outputs,
old journals and evidence remain intact. Source files at shared seams may change;
capture prechange source hashes/copies and verify every historical store. Old
live runners retain their old hash gates and must not be silently repointed.

## Implementation and checks

Primary owns config, reducer/replay compatibility, context/broker/worker binding,
runtime admission and interpretation. A bounded worker may implement only the
pure ranked matcher and deterministic unit fixtures under the defined contract.
No delegation of privilege, model execution or persistence decisions.

Checks cover exact compatibility; plurals/case/Unicode; distractor and true
no-match queries; deterministic ties and result bounds; lineage/revisions and
tombstones; positive/negative journal replay; strict profile selection; recent
exchange correction/order/provenance; no current/incomplete/future exchange leak;
byte and actual-token eviction; mismatched worker/broker modes; and real isolated
workers with synthetic inference. Run affected historical regression verifiers
and validate all historical stores before live use. No safety decision comes
from a local model evaluation.

## Frozen live comparison

Use three independent conditions: legacy exact retrieval with no automatic
dialogue; ranked retrieval alone; ranked retrieval plus recent dialogue. Do not
reuse A16's unsuccessful added system guide. Keep model, sampler, grammar,
3072-token input budget, six-call event limit and containment unchanged.
Reuse A16's sixteen natural requests and include new multi-document distractors
in a separately defined four-request transfer batch. Freeze cases, evaluator,
source hashes and condition order before any generation. Each batch starts an
empty independent store; each event uses a fresh worker. Alternate condition
order between batches. Same goals/corpora across conditions; record that histories
and lineage IDs differ, so this is a small multi-turn pilot, not identical-token
testing or a population reliability estimate.

At most 60 events, 360 generations, and 1800 seconds including a 20-second cleanup
reserve. Existing per-stream/event/worker bounds remain. No retries, changes to
prompts/scorers or retuning after live results. Infrastructure failure, ambiguous
intent, unknown terminal reason, blocked review or input-budget failure ends the
suite; behavioral failures remain results. Verify worker exit and idle inference.
Busy or incompatible runtime means no model switching or eviction: preserve the
candidate and report the gate. No job survives the turn.

## Assessment and handoff

Separate factual correctness, source support, unknown handling, callback accuracy,
social response quality, unnecessary repair, calls/tokens/elapsed time and safety
check evidence. Direct-dialogue sources may support a callback only if the actual
recorded context includes the relevant exchange; unavailable/evicted text does
not count. Keep absent-fact and social cases outside the factual-task denominator.
Model-server restart tests remain conditional on a useful conversational baseline.
Update the adaptation plan, canonical review links and an A17 review; retain all
first failures, historical results and unrelated dirty work. Human acceptance and
release remain distinct from implementation or live qualification.
