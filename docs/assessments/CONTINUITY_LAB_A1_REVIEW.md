# Continuity Lab A1 retrieval and context review

Candidate status: candidate_complete for the synthetic Step 2 implementation.
Human merge/release outcome: not performed; live qualification remains separate.

## Authority and result

The owner approved continuation after the A0 delivery and Step 2 description.
Scope is [the A1 brief](../soul/CONTINUITY_LAB_A1_BRIEF.md), extending
[the adaptation plan](../soul/CONTINUITY_LAB_ADAPTATION_PLAN.md). This is an
isolated library plus synthetic verifiers, not a deployed Soul skill or worker.

- Explicit `search` and `read` expose only current eligible notes, completed
  reply exchanges, or operator-supplied text documents in the same lineage.
  Results carry revision, digest, provenance and zero-based character spans.
  The audit journal, pending/wait/failed events and ordinary Soul state are not
  retrieval collections. Observed conversation is not a verified fact.
- Unicode-case-folded lexical AND search uses deterministic ranking, bounded
  result counts/bytes and a fresh projection, without a persistent stale index.
- Revision-checked tombstones remove current note retrieval eligibility while
  retaining old evidence; a matching later revision may restore a note. No
  physical purge or shared-memory promotion API exists.
- Context includes the fixed minimal instruction/tool contract, complete current
  request and whole response/result groups. Nothing from old history, notes or
  corpus is automatically injected. Older groups drop oldest-first as needed;
  the newest group and current request cannot be silently truncated or omitted.
- Each intent persists its exact formatted input and an inclusion/omission
  manifest bound to lineage, configuration, corpus, formatter and retrieval
  policy. Both append and replay verify it and the actual retrieval result.
  Source contents remain data rather than permission or verified claims.
- Default fixture budget is 4096 total, 768 output, 256 margin, 3072 input.
  `fake_utf8_bytes_div4_v1` is a deterministic test counter, NOT an estimate
  or validation of the installed Qwen template/tokenizer. Essential overflow
  commits a typed terminal failure before another backend call.

The restart demonstration creates a note, closes/reopens its store, confirms
that a fresh event contains no old note/history/corpus text, and explicitly
searches/reads the note. Its result then appears in the next formatted input;
unrelated source text remains absent. This demonstrates data flow with scripted
responses, not that Qwen autonomously chooses useful retrieval or learns.

## Changed paths

```text
lib/soul_core/continuity_lab/config.rb
lib/soul_core/continuity_lab/actions.rb
lib/soul_core/continuity_lab/retrieval.rb
lib/soul_core/continuity_lab/context_builder.rb
lib/soul_core/continuity_lab/store.rb
lib/soul_core/continuity_lab/runtime.rb
lib/soul_core/continuity_lab/fake_backend.rb
scripts/verify-continuity-lab-context-a1.rb
scripts/verify-continuity-lab-recovery-a1.rb
docs/soul/CONTINUITY_LAB_A1_BRIEF.md
docs/soul/CONTINUITY_LAB_A0_BRIEF.md
docs/soul/CONTINUITY_LAB_ADAPTATION_PLAN.md
docs/assessments/CONTINUITY_LAB_A1_REVIEW.md
docs/soul/HUMAN_REVIEW_GATE.md
skills/_template/REVIEW.md
```

The original A0 files were already uncommitted; preserve that fact and unrelated
dirty work. No commit, merge, package, service, deployment, network, model or GPU
change occurred. Only temporary synthetic test stores were created/cleaned up.

## Required commands and evidence

Run with `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`:

| Verifier | Result |
| --- | --- |
| `scripts/verify-continuity-lab-core-a0.rb` | PASS: 21/21 |
| `scripts/verify-continuity-lab-recovery-a0.rb` | PASS: 149 |
| `scripts/verify-continuity-lab-context-a1.rb` | PASS: 30/30 |
| `scripts/verify-continuity-lab-recovery-a1.rb` | PASS: 94 |

Pinned-Ruby syntax checks for all seven module files and four verifiers pass.
Changed-document links/fences and changed-source whitespace checks pass.
No ordinary chat/context/provider caller changed, so broader live/host and
unrelated application regressions were not run.

The A1 recovery suite exercises search/read/tombstone before-stage, after-stage,
and after-commit faults followed by close/open and explicit resume; only the
next scripted response is called and an effect is committed once. It also
rewrites committed intent/result records with recomputed hashes and verifies
that replay rejects their semantic forgery. Other cases include exact budget
and one-unit overflow, oversized newest group, ambiguous intent with zero new
backend calls, UTF-8 spans, escaped-byte truncation, corpus quota and schema drift.

## Review and corrections

Luna High owned the bounded context verifier only. Sol High performed a focused
read-only review; primary retained integration, memory and recovery decisions.

- Confirmed defect: lowercase matching missed Unicode final-sigma equivalence.
  Replaced it with full case folding; actual Store/Runtime tests cover both
  sigma and the expanding sharp-S mapping. Policy version is bound to context.
- Evidence gaps: initial verifier tested append rejection rather than tampered
  committed replay, a completed restart rather than interruption, and only a
  small result. The primary A1 recovery verifier now covers those exact cases.
- Primary additionally rejected over-quota corpus manifests before creating a
  store. No unusable oversized store is left by that validation failure.

## Compatibility, limits and next gate

Store schema is `soul.continuity_lab.a1`; old A0-schema stores are refused, not
silently migrated or overwritten. There were no production A0 lineages in this
scope. The default `raw_fixture` mode remains available only for A0 regressions;
retrieval requires explicit `context_mode=explicit_v1`. All backends remain fake.

Logical isolation/validation and filesystem checks do not prove OS containment
or tamper resistance against the owning user. Reads/scans and context counts
are bounded, but no hard realtime disk-I/O timeout is claimed. Tombstones are
eligibility changes, not privacy erasure of past journal/results.

No automatic summary, optional pre-rollover prompt, pin/move, embeddings,
checkpoint/fork, dashboard, timer, code execution or browser was added. These
remain named later capabilities, not silently passed requirements.

Next: Step 3 worker containment and coordinated inference-access design, with
an exact approved deployment scope before live application. Real Qwen template
token counts and usefulness require Step 4; this packet supplies no such claim.
