# Continuity Lab A1 retrieval and context brief

Status: approved development scope following the owner's "approved, let's
continue" after the A0 delivery and explicit Step 2 next-step description.
This extends the [A0 brief](CONTINUITY_LAB_A0_BRIEF.md), not live authority.

## Outcome and boundaries

Complete Step 2 of the [adaptation plan](CONTINUITY_LAB_ADAPTATION_PLAN.md):
explicit bounded lexical retrieval, revision/span provenance, and reproducible
budgeted context with whole-group rollover. Primary owns memory/recovery and
integration. A bounded worker may own the new verifier. Preserve unrelated work.

Only synthetic temporary stores and in-process scripted responses are used.
No ordinary Soul memory/history, archive instructions, evaluation answer keys,
live input collection, inference, UI, service, network, package, or deployment
change. No new persistent process. No automatic corpus discovery/import.

## Contracts

- `Config.new("context_mode" => "explicit_v1")` selects A1. The default
  `raw_fixture` preserves A0 test behavior; retrieval tools are denied there.
  Store schema becomes `soul.continuity_lab.a1`. Old A0 stores are not silently
  migrated or overwritten; prior stores were disposable synthetic fixtures.
- `Store.create(..., corpus: [{"id" => "manual", "content" => "Synthetic text"}])`
  accepts only explicit UTF-8 text, unique logical IDs, at most 32 documents,
  8192 bytes each and 65536 bytes total. Its immutable snapshot/digest is in the
  private manifest. Reopen validates it; no file paths or remote URLs are fetched.
  Reject a manifest that exceeds the configured store quota before creation.
- `search` arguments: `lineage_id`, `collection` (`notes`, `history`, `corpus`),
  `query` (1-128 bytes, lexical terms required), `limit` (1-8).
- `read` arguments: `lineage_id`, `collection`, `id`, `revision` (positive integer),
  `start` (zero-based character offset), `length` (1-1024 characters).
- All arguments/fields/types are exact. Cross-lineage access fails. Search uses
  Unicode full-case-folded letter/number terms, AND matching, summed occurrence
  score, then logical-ID order. Results are bounded to 8192 encoded bytes;
  snippets are at most 160 characters with explicit spans. Rebuild the small
  projection from validated state on every query; no persistent search cache.
- Notes are current revisions of unverified model claims. `note.tombstone`
  takes `note_id` and `expected_revision`, advances the revision and removes
  retrieval eligibility, not journal evidence. A matching later write may
  restore eligibility. IDs still occupy quota; no purge/move/pin API is added.
- Eligible history consists only of completed reply exchanges, revision 1:
  canonical JSON text containing `user` and `assistant`. Exclude current,
  failed/wait events, calls, control metadata and the audit journal. Observed
  dialogue is not a verified fact. Corpus text is source data, not authority.
- Every result includes collection/ID/revision/content digest, provenance and
  character span. Stale revision reads fail; no fallback to an unintended
  revision. Result/effect is durably reconciled against the stored response.
- Context has a fixed versioned minimal instruction and tool contract, the
  complete current request, and complete prior response/result groups from
  this event. No automatic note/history/corpus injection. Newest result group
  is essential; older groups drop oldest-first only when needed. No summaries,
  pinning, pre-rollover note opportunity or forced reflection. Omitted text
  remains in the journal but is not automatically reinserted.
- Persist formatted input and exact inclusion/omission manifest with intent,
  before calling the backend. Bind lineage, config, corpus and formatter hashes,
  source spans/revisions, whole groups, input count, output reserve and margin.
  The formatter digest also binds the versioned lexical retrieval policy.
  Replay recomputes and validates the same context; ambiguous intent still blocks.
- Default budget: 4096 total, 768 output, 256 margin, 3072 input. Counter is
  explicitly `fake_utf8_bytes_div4_v1` (ceil serialized UTF-8 bytes / 4), not a
  Qwen tokenizer estimate or qualification. Boundary tests may lower total to
  128; upper bound stays 4096. Output range 1-2048, margin 0-1024, sum < total.
  Essential overflow commits `failed/context_budget_exceeded` without a model
  call. No silent request truncation. Installed template/tokenizer comes later.

## Owned paths and acceptance

`lib/soul_core/continuity_lab/`, new
`scripts/verify-continuity-lab-context-a1.rb`,
`scripts/verify-continuity-lab-recovery-a1.rb`, existing A0 verifiers if needed,
this brief, adaptation plan, A1 review packet, canonical gate/template links.

Use `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`:

1. Core and recovery A0 verifiers: no regression in prior evidence contracts.
2. A1 context verifier: explicit search/read, revision changes/tombstones, result
   bounds, source spans, lineage/path denial, synthetic corpus isolation, no
   implicit memory, formatted-budget edges, whole-group rollover and optional
   no-note behavior. Include restart/replay and forged context/result failures.
3. A1 recovery verifier: interrupted search/read/tombstone commits with close/open,
   persisted context/result tampering, explicit recall after restart, Unicode
   folding/spans, encoded-result truncation, exact budget edges, essential-group
   overflow, ambiguous intent, and corpus/schema boundaries.
4. Syntax, changed-file whitespace and documentation-link checks.

Candidate completion covers fake tests only. Live containment, real Qwen
token accuracy/usefulness, dashboard, checkpoint/fork, scheduler and human
experiment acceptance remain later gates. No commit/merge/release is implied.
