# Continuity Lab A3 v2 comparison review

Historical comparison. Subsequent authorized repairs and results are in the
[A4 review](CONTINUITY_LAB_A4_REVIEW.md); the v2 evidence below is unchanged.

Date: October 8, 2026 (America/New_York)
Candidate status: requires_repair / targeted live requalification.
Authorized comparison: complete. Dashboard, merge and release: not performed.

## Outcome and scope

The second approved 20-case batch scored **13/20**, compared with **7/20** in
the [original v1 baseline](CONTINUITY_LAB_A3_REVIEW.md). Most importantly, v2
actually created a note, read it in a fresh worker process, and retrieved it by
search. Correction, subsequent deletion and long-sequence adherence remain
unqualified. This is not evidence of learning or readiness for ordinary chats.

The owner approved this one comparison after the explicit v2 proposal. The
[A3 brief](../soul/CONTINUITY_LAB_A3_BRIEF.md) retained the 1,200-second,
60-generation, synthetic-only limits. No prompt, parser, settings or scoring
change was made during the run; no failed response was repaired. Both approved
batches are now consumed. A further live run needs a new bounded scope.

Executed with repository-pinned Ruby:

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/qualify-continuity-lab-qwen-a3.rb --approved-quiet-window
```

Completed at **01:16:51 EDT**, using 240.062 seconds and 56 generation calls.
All 20 cases were scored. Exit 1 records behavioral failures; the summary has
no infrastructure failure. No timeout or uncompleted test process remains.

## Retained evidence and comparability

Separate owner-private, Git-ignored root:
`Soul/runtime/qualification/continuity-lab-a3-20261008T051251Z/`

Its `baseline.json`, `calls.jsonl`, `case-*.json`, `summary.json` and
`worker/store/` preserve inputs, raw responses, exact token IDs, committed tool
results, timing and replay evidence. The original v1 root was not overwritten.
No upload, ordinary Soul memory ingestion, Git addition, deletion, deployment,
Core/profile switch, service restart or network change occurred. Existing
backups may include this locally retained evidence.

Baseline comparison confirms unchanged model/server file hashes, settings,
case specifications, configuration and host fingerprint. V2's recorded prompt
version is `qwen_envelope_v2_explicit_examples`. Each batch has a fresh randomly
generated lineage ID. These are two illustrative runs, not a statistical or
perfectly byte-identical causal experiment.

| Measurement | Original v1 | Explicit-envelope v2 |
| --- | --- | --- |
| Scored cases passing | 7/20 | 13/20 |
| Generation calls | 42 | 56 |
| Total run time | 170.309 s | 240.062 s |
| Generated output tokens | 2,200 | 2,215 |
| Rejected malformed actions | 21 | 5 |
| Input tokens per call, range / median | 557–1,025 / 637.5 | 785–2,623 / 894.5 |
| Generation response seconds, range / median | 1.52–5.21 / 3.64 | 1.88–7.58 / 3.66 |
| Server generation tokens/s, range / median | 24.97–29.53 / 26.66 | 21.39–30.68 / 25.68 |
| Prompt ingestion tokens/s, range / median | 430.66–484.56 / 466.23 | 404.52–485.35 / 457.24 |
| Sampled GTX 1070 allocation | 5,283–5,301 MiB, 63 samples | 5,301–5,303 MiB, 77 samples |

Fewer malformed outputs did not make the batch cheaper: repeated valid-shaped
but unsuccessful actions consumed additional calls. GPU samples are not a
continuous peak-VRAM measurement. All 56 v2 input counts match reported
`tokens_evaluated`; none reported truncation. No context group was omitted.
The largest input remained below the 3,072-token input ceiling; live rollover
and exact-token adaptive packing have therefore **not** been demonstrated.

## Audited behavioral evidence

The harness score alone is insufficient: some predicates check tool names and
reply text without binding successful results to the intended target, revision,
span or order. Luna's read-only scoring/dependency map identified these limits;
the primary independently inspected committed results and input envelopes.
Scores below remain the unchanged original predicates, not a retrospective
rescore or claim that every success was first-attempt.

| Cases | Recorded outcome | What the underlying evidence establishes |
| --- | --- | --- |
| 1, reply | Fail | Echoed the instruction instead of answering `four`. |
| 2–3, wait / Unicode | Pass | Correct wait and exact `violet café` reply. |
| 4–6, note seed / read / search | Pass | Committed `beacon` revision 1, read it from a fresh worker, successfully searched and read the same note. |
| 7, correction | Fail | Used the wrong note ID, `amber-beacon`, then repeated rejected writes until the six-call limit. |
| 8–10, corrected read / tombstone / search | Fail, dependent | Revision 2 and a tombstone never existed. These do not independently test successful correction/deletion. |
| 11–12, corpus search / read | Pass | Successful search and reads of `corpus/charter` revision 1 support the answer `blue`; search first needed one syntax retry. |
| 13–14, no automatic corpus / history | Pass | Recorded input envelopes contain no prior sources or tool groups; both replies were `UNKNOWN`, without tools. |
| 15, history search | Pass | After one malformed attempt, successful history search returned the earlier `03-unicode` exchange, supporting `violet café`. |
| 16, multi-step | Pass | Successful corpus search followed by a successful read of the returned `charter` revision, then the supported answer. |
| 17, optional no-note | Pass | Correct arithmetic reply `15`, no tool or note write. |
| 18, missing source | Fail | Returned `MISSING` after an invalid bare read action; no actual source read established absence. |
| 19, unavailable tool | Pass | Replied `UNAVAILABLE`; no tool attempt. This is behavior evidence, not the safety boundary. |
| 20, long multi-step | Fail, partial capability | Three successful reads and a grounded final marker, but not the requested four reads or order. No rollover. |

Case 4 committed `beacon`, expected revision 0, content `amber beacon code 73`.
Case 5 read revision 1 with its actual lineage, returning the same content and
digest. Case 6's search and follow-up read also succeeded. This is genuine
durable retrieval across fresh OS worker processes, not merely a final reply
claiming to have saved something, and not a Qwen service restart.

Case 7's first write used `note_id: amber-beacon`, `expected_revision: 1`,
`content: 91`. The remaining five writes corrected the content but retained the
wrong ID. All were rejected with `revision_conflict`. The existing `beacon`
note stayed intact. Cases 8 and 9 requested nonexistent revision 2; neither
proved a defect in the deterministic storage implementation. Case 10 then
lacked the tombstone prerequisite. The errors are connected, not four separate
independent storage failures.

Case 20 read `corpus/long` revision 1 at offsets **0, 3072, 2048**, each requesting
length 1024. All succeeded; the 3072 read returned `[3072,4044)` and contained
`Final marker TEAL-42.`. The reply was supported, but offset 1024 was skipped
and the requested sequence was not followed. Preserve that distinction rather
than describing retrieval as wholly broken or accepting the case as rollover.

Cases 13–14 explicitly instruct `UNKNOWN`; they are smoke checks, not robust
evidence of general abstention or absence of every possible covert state path.
The no-automatic-injection claim is supported by the retained empty source
envelopes and deterministic context tests, not the model's compliance alone.

## Integrity, runtime and verification

Independent offline reopening of the v2 journal passed integrity:

- Lineage: `e7ed24b9d9b461ec52ebafe5adaaa278`.
- 192 transactions, 20 events, one note.
- Head: `1c9d31f153861b51c3e7916787d1bf8dbe2fdea9152a416f7690428555e8a186`.
- Final note: `beacon`, revision 1, not tombstoned; exact original content intact.
- Note digest: `4e91c8b1ec80833f64855ae8329b06f59669cc30891e368c87c3049f93b0c829`.

The final broker observation verified idle. Independent post-run systemd
read-back found `llama-server.service` active/running with the original
**MainPID 3058**. The harness did not switch or restart it. Operator quiet-window
coordination still does not enforce exclusion of direct external clients.

`verify-continuity-lab-qwen-a3.rb` was rerun before this batch: **15 checks,
0 failures**. The unchanged A0–A2 code retains its previously recorded test
evidence; those suites were not rerun for results-only documentation edits.
This handoff changes documentation only, not the runtime or scorer. Local
relative-link, whitespace and recorded-result consistency checks passed.

## Recommended next bounded scope

Do not wire the dashboard or repeat another unmodified full batch yet.

1. Strengthen the harness first: bind assertions to actual result success,
   intended IDs/revisions/spans and order. Report unmet prerequisites explicitly;
   keep an end-to-end chain, but add independent correction/tombstone fixtures.
2. Make a separately versioned interface condition with structural JSON action
   constraints and complete tool examples. Preserve deterministic argument and
   permission validation; never silently rewrite semantic errors or wrong IDs.
3. Design and deterministically test bounded handling of repeated failed actions
   and accurate reporting of unresolved results. Any change to termination or
   recovery behavior needs explicit contract coverage, not just a prompt rule.
4. Retest the failing capabilities in a new bounded live window. Include a case
   that provably omits context and retrieves the needed evidence again, rather
   than assuming a long string forces rollover.

These are proposals, not changes made in this comparison. This batch supports
continuing the fixed-model experiment, but does not establish reliable
correction, deletion, long-sequence adherence, sustained continuity or learning.
