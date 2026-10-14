# Continuity Lab A4 focused qualification and adapter repair

Historical packet for the first A4 window and prepared v3.1 repair. The later
[fresh v3.1 qualification](CONTINUITY_LAB_A4_V3_1_REVIEW.md) supersedes its
"not live-generated" status; the original results below are unchanged.

Date: October 8, 2026 (America/New_York)
Status: implementation checked; live qualification **incomplete**.
Current candidate: `qwen_envelope_v3_1_ordered_grammar`, not live-generated.
Dashboard / merge / release / ordinary-memory activation: not performed.

## Scope delivered

The owner approved the next steps in the [A3 v2 review](CONTINUITY_LAB_A3_V2_REVIEW.md).
The [A4 brief](../soul/CONTINUITY_LAB_A4_BRIEF.md) records the bounded implementation
and one new focused live batch. Implemented:

- A pure scorer binding actual actions/results to IDs, lineage, revisions,
  spans, content and sequence; it rejects unrelated successful side effects.
- Explicit unmet-prerequisite reporting and skipping instead of wasting model
  calls on a chain whose earlier mutation failed.
- Independent correction and tombstone fixtures, labeled deterministic setup,
  not model-created notes; a separate reduced-packing-budget rollover fixture.
- An opt-in, configuration-bound `consecutive_equivalent_failure_v1` policy:
  two consecutive equivalent failed tool actions with the same reason terminate
  `failed/repeated_failed_action`. No semantic action repair or false success.
- A separately versioned constrained action format, plus unchanged runtime
  argument validation, admission, output/time bounds and recovery protection.

Primary retained ownership of runtime, journal, isolation and host execution.
Luna mapped/scoped and implemented the pure scorer; primary integration review
corrected its initial nested-result assumption, strict parsing and evidence
checks before any live use. Sol reviewed the persistence boundary and found
that replay could accept a different terminal failure reason after a repeat.
Primary fixed that and added negative terminal/extra-intent regression checks.

## The one live batch

Executed once using pinned Ruby and
`scripts/qualify-continuity-lab-qwen-a4.rb --approved-quiet-window`.

Retained separate owner-private, Git-ignored evidence root:
`Soul/runtime/qualification/continuity-lab-a4-20261008T062825Z/`

The run ended at **02:30:01 EDT**, after **96.081 seconds** and **17 generations**.
The tested condition was `qwen_envelope_v3_structural_actions`, NOT the later
ordered-grammar repair. Sampler/model/server stayed unchanged; no prompt or
scorer was adjusted during the run. The resident server accepted the structural
JSON schema and returned valid action shapes, but this did not ensure the
correct action was selected.

| Outcome | Cases |
| --- | --- |
| Passed, result-bound | 01 reply; 09 independent tombstone; 10 missing source; 11 search/read |
| Behavioral failure | 02 note seed; 08 independent correction |
| Skipped for unmet prerequisite | 03 read; 04 correction; 05 corrected read; 06 tombstone; 07 search |
| Interrupted before scoring | 12 four reads: exact input-token ceiling rejected next generation |
| Never started | 13 omitted-context/re-read |

That is **4 passing and 2 failing completed tests**, 5 explicit skips, one
interrupted test and one unstarted test, out of 13 planned cases. Do not compare
this catalog's fraction directly with the differently designed A3 7/20 or 13/20.

Raw-summary bookkeeping erratum: the original `scored_cases: 11` includes five
skips, and `not_started_cases: 2` includes the attempted-but-unscored case 12.
Raw evidence is unchanged. The harness now separates recorded vs scored cases
and counts truly unstarted cases correctly for a later run.

All 17 received generations matched their submitted input-token counts; none
reported truncation. Submitted inputs ranged 955–2,568 tokens and outputs
totaled 687 tokens. There were no rejected malformed actions in the recorded
case results. All 24 GPU samples reported 5,303 MiB of 8,192 MiB on the GTX 1070.
These are samples, not a continuous peak-VRAM measurement or a model benchmark.

## What failed and what was preserved

The seed request asked for `note.write` but Qwen emitted `note.tombstone` for
`beacon` twice. Both attempts returned `not_found`; the new guard stopped the
event after two calls. No chain note existed, so five descendants were skipped.

The independent correction request likewise emitted `note.tombstone`, this time
successfully tombstoning the **synthetic** `correction` fixture at revision 2.
It then repeated the stale-revision action twice and stopped on the guard.
The scorer did not count that successful but wrong effect as a correction.
No ordinary Soul note or user data was involved. The independent deletion
fixture was successfully tombstoned as requested in its own case.

Case 12 read offsets **0, 1024, 3072, 3072**, all successfully; it skipped 2048
and repeated 3072. Before call index 4, the exact tokenizer measured **3,278**
input tokens, above the 3,072 ceiling. Generation was refused; the foreground
worker was terminated/reaped and the run stopped. The unresolved model intent
remains in the retained journal with event state `pending`; no automatic
resume or inference was attempted. Successful duplicate reads are deliberately
not mistaken for repeated failures by the new failure guard.

The final observer verified idle; independent systemd read-back verified the
unchanged active/running `llama-server.service`, MainPID **3058**. No model/Core
switch, restart, network change, upload, Git addition, merge or deletion occurred.

Independent offline journal integrity checks passed:

| Store | Transactions / events / notes | Head digest |
| --- | --- | --- |
| chain | 12 / 2 / 0 | `2fda97f6ea35b0856852e85da0e4d332c1cb300e393e3de8b426a036a59111c4` |
| independent | 63 / 7 / 2 | `e6497a5afb120854e590db5c78f881d63958587c63bf6053b00102cd6b6a8e9f` |
| rollover | 0 / 0 / 0 | no committed transactions |

Independent-store event counts include two labeled setup events. Both previous
A3 journals also reopened with unchanged head digests and original contents.

## Post-run diagnosis and prepared repair

The adapter's `ContinuityLab.encode` sorts object keys recursively. That sorted
the JSON schema's properties as **action, arguments, tool**. The matching local
llama.cpp converter iterates ordered properties and generates the same order.
Reproducing conversion from the actual canonical schema confirmed that tool
selection was constrained until after arguments had been generated. The
observed tombstone outputs follow that order. This is a confirmed interface
defect and plausible contributor to selection errors, not proof of the entire
cause or of repaired model behavior.

The prepared **v3.1** candidate sends a fixed GBNF grammar generated from the
same structural schema with **action, tool, arguments** order. Its literal text
survives JSON canonicalization. The generated-file notice and deterministic
checks bind this property; runtime parser, quotas and journal checks are not
relaxed. The schema remains source for the reviewed grammar; there is no remote
schema fetch or runtime dependency on the converter.

V3.1 also removes duplicated SYSTEM/PROTOCOL text from the outer wrapper; the
explicit envelope still contains it. A post-run **formatter/tokenizer-only**
check against the unchanged local server measured the exact rejected envelope
at **3,045 tokens**, down from 3,278, with the non-thinking suffix intact.
No `/completion` was invoked. This proves that particular prompt now fits,
not that arbitrary future tool sequences will fit; the ceiling remains active.

Neither this grammar nor the reduced wrapper has been used for live generation.
The run is not retroactively rescored or labeled a v3.1 success. The approved
single batch is finished; another live qualification is the next gate.

## Verification and remaining limits

Commands use `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`:

| Script | Evidence |
| --- | --- |
| `verify-continuity-lab-core-a0.rb` | 21 checks passed |
| `verify-continuity-lab-recovery-a0.rb` | 149 checks passed |
| `verify-continuity-lab-context-a1.rb` | 30 checks passed |
| `verify-continuity-lab-recovery-a1.rb` | 94 checks passed |
| `verify-continuity-lab-admission-a2.rb` | 14 checks passed |
| `verify-continuity-lab-isolation-a2.rb` | 34 actual isolated-worker checks, synthetic transport; rerun for v3.1 |
| `verify-continuity-lab-qwen-a3.rb` | 15 legacy/transport checks passed, including after v3.1 preparation |
| `verify-continuity-lab-scoring-a4.rb` | 18 negative/positive scoring checks passed |
| `verify-continuity-lab-a4.rb` | 38 policy/recovery/catalog/v3.1 checks passed |

The full catalog passes against scripted fixtures, including correct writes,
independent correction/deletion and a manifest-proven omission followed by
re-reading the same source. This is deterministic capability, **not live Qwen
acceptance**. Local schema-to-grammar generation succeeds without diagnostics;
the prepared grammar is verified against that output. Source syntax, review
links and whitespace checks pass.

Next: one new bounded v3.1 live qualification with separately retained evidence,
unchanged model/sampler, and explicit quiet-window admission. Keep dashboard
integration on hold until correction, full required read sequences and actual
omitted-context recovery qualify. General reliability, optional-note utility
across sustained interaction, and learning remain separate experimental questions.
