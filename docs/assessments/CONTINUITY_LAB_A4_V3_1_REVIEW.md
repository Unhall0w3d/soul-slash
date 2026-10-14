# Continuity Lab A4 v3.1 fresh live qualification

Historical v3.1 packet. The subsequent
[A5 repair and qualification](CONTINUITY_LAB_A5_REVIEW.md) supersedes the
unimplemented actual-token-packing status; these raw results and the interrupted
journal remain unchanged.

Date: October 8, 2026 (America/New_York)
Status: **partial live qualification; Step 4 remains open**.
Dashboard / ordinary-memory activation / merge / release: not performed.

## Scope and execution

The owner's "alright, let's continue please" approved the one fresh bounded
window proposed in the [preceding A4 review](CONTINUITY_LAB_A4_REVIEW.md).
The [A4 brief](../soul/CONTINUITY_LAB_A4_BRIEF.md) records this authorization.
No live tuning, automatic retry or second batch occurred.

Command, executed once:

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/qualify-continuity-lab-qwen-a4.rb --approved-quiet-window
```

Private, Git-ignored retained root:
`Soul/runtime/qualification/continuity-lab-a4-20261008T174435Z/`.
Evidence includes `baseline.json`, `calls.jsonl`, `summary.json`, case receipts,
labeled synthetic setup receipts and three journal stores. All 138 paths were
checked for no symlinks and no group/other permission bits. Earlier batch roots
were not resumed or overwritten.

The run ended at **13:46:37 EDT**, after **122.334 seconds**, with exit 1:
**27 generations**, **11 passing completed cases**, one interrupted/unscored
case and one unstarted case. No prerequisite skips or completed failing cases.
This is not a 13-case pass or a general reliability estimate.

## Actual outcomes

| Cases | Result established |
| --- | --- |
| 01 | Exact reply, no tools |
| 02–05 | Model-created note at revision 1; fresh-worker retrieval; correction to revision 2; fresh-worker retrieval of the corrected text |
| 06–07 | Note tombstoned at revision 3; subsequent search returns no live match |
| 08–09 | Independently seeded synthetic note corrected correctly; separate synthetic note tombstoned correctly |
| 10–11 | Actual missing-source result recognized; corpus search followed by exact read and supported answer |
| 12 | First four required reads succeeded in order; model repeated the fourth read instead of answering; next prompt rejected before generation |
| 13 | Omitted-context/re-read test never started |

The eleven completed cases used eleven distinct worker PIDs. Actual tool JSON
preserved `action, tool, arguments` order. Every completed case had zero invalid
actions. Case 10's `failed_or_malformed_attempts=1` is the deliberately expected
`not_found` tool result, not an unexpected error or malformed action.

Luna Low independently mapped the published case receipts and raw responses to
actual tool results; primary independently verified journal state, host/runtime
boundaries and aggregate metrics. No LLM assessment substitutes for enforcement.

## Remaining failure: two distinct layers

Case 12 requested four reads of `corpus/long`, revision 1, length 1024, at offsets
**0, 1024, 2048, 3072**, followed by the final marker. Unlike the earlier v3 run,
all four requested reads succeeded in the correct order. The fourth result
contained `Final marker TEAL-42.`

At call index 4, the prompt contained all four successful results and measured
**3,066 actual tokens**, within the unchanged 3,072 limit. Qwen nevertheless
issued another successful read at 3072 instead of replying. The next prepared
prompt, index 5, measured **3,774 actual tokens**; the broker rejected it before
generation. There is no terminal reply or completed case-12 score. The extra
successful action is not silently dropped or counted as passing adherence.

The persisted context manifest for that rejected input reports:

- Counter: `fake_utf8_bytes_div4_v1`, estimate **2,253**, fixture budget 3,072.
- Included groups: `[0, 1, 2, 3, 4]`; omitted groups: `[]`.
- Formatted digest:
  `4b0d21fb54279f7638141bcfeb02156b6e93e380a26238ed511397333f88c482`.

That digest matches the broker's rejected envelope receipt. Journal manifests
also show no omissions at the earlier case-12 calls. Thus the repeat was **not**
recovery from omitted context. The counter used by the fixture packer estimates
only serialized-envelope bytes; it is not the installed tokenizer or complete
rendered prompt. The exact broker guard works, but live context packing still
does not use that real count to remove eligible old groups before admission.
Prompt deduplication reduced overhead; it did not solve this general mismatch.

These observations support two separate conclusions: a live context-packing
integration gap, and an observed failure to stop reading after the requested
sequence. Fixing packing alone must not be advertised as fixing model adherence.
No OOM, service crash, token truncation or model switch was observed in this run.

## Retained state and host read-back

All stores reopened successfully through journal validation:

| Store | Transactions / events / notes | Head digest |
| --- | --- | --- |
| chain | 46 / 7 / 1 | `9ceb8a53c365f2e7a29dc6a9e11c42fd0283645fa45355246785ba1ca230ac13` |
| independent | 62 / 7 / 2 | `13a8feda6a1e386c6323bd75d4c04e7dd25094bc2d187df04284092c38a8850b` |
| rollover | 0 / 0 / 0 | no committed transactions |

The chain note `beacon` is revision 3, tombstoned. Independent `correction` is
revision 2 with `repaired code 82`; `deletion` is revision 2, tombstoned.
Independent event counts include the two explicitly labeled fixture events.
Case 12 remains `pending` with a retained unresolved intent and null response;
the worker was reaped. This is **not a still-running job**. No recovery/resume
was invoked; that journal must not be silently resumed or relabeled complete.

The harness verified idle on exit. A separate primary admission/observer check
confirmed zero active slots, no pending transition and the unchanged profile.
Independent systemd read-back showed active/running `llama-server.service`,
MainPID **3058**. No `continuity-lab-worker.rb` process remained (process search
exit 1 indicated no matches, not a failed runtime observation).

## Fixed conditions and verification

Same Qwen3-8B-Q4_K_M, GTX 1070 8 GiB, llama.cpp `b9851-0eca4d490`, one resident
4,096-token slot, non-thinking mode and sampler. Protocol:
`qwen_envelope_v3_1_ordered_grammar`; case catalog `result_bound_focused_a4_v1`.
Model/server/template hashes match the approved pins. All recorded Ruby source
hashes still match disk, and the recorded settings including literal grammar
match the current candidate. No source implementation changed during this turn.

- 27 received generations: submitted input range **716–3,066**; all server input
  counts match; none reports truncation; **1,022 output tokens** total.
- 39 GPU samples: all **5,303 MiB / 8,192 MiB**. Sampling is not continuous peak
  measurement or a general performance benchmark.
- Fresh focused deterministic checks: **38/38 A4** and **18/18 scorer** passed.
- Existing A0–A3, actual-isolation and grammar-conversion evidence is retained
  in the preceding review; unchanged source does not warrant repeating it all.
- Operational preflight's separate restricted CLI could not reach its provider;
  it does not attest to this app turn's permissions or an app outage. Exact
  host checks/live execution used supported operation-specific escalation.

## Recommended next bounded change

1. Add versioned real-tokenizer-aware context preparation. Preserve mandatory
   instructions/current request/newest result; remove only eligible whole older
   groups, recording the exact included/omitted sources before generation.
   Keep the 4K context, output reserve and hard ceiling; do not increase them to
   conceal an inaccurate packer. Preserve deterministic replay and old journals.
2. Qualify that path offline with retained prompts and deterministic tokenizer
   fixtures, including essential-input overflow, stale/mismatched receipts and
   interrupted preparation. Do not silently change the recorded model input
   after the journal intent or weaken digest/replay checks.
3. Use a new approved focused window for complete-read/terminal-reply adherence
   and actual omitted-context re-read, with a short note-chain regression. Keep
   repeated successful reads legal in the generic runtime: re-reading omitted
   evidence is a desired capability, while an unrequested duplicate stays a
   task-scoring failure. Do not force the expected action or inject a summary
   of progress on the model's behalf.

This is a proposed follow-up, not implemented or live-qualified here. Dashboard
integration remains held. Optional-note utility in sustained interaction,
paraphrase reliability, and any learning claim remain separate later questions.
