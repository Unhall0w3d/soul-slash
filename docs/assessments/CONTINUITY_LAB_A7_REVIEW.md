# Continuity Lab A7 streaming diagnostics and comparison

Date: October 8, 2026 (America/New_York)
Status: **diagnostic transport implemented and exercised; four behavioral cases
completed and failed; no infrastructure interruption**. Step 4 remains open.
No dashboard, ordinary-memory activation, service/model change, merge or release.

## Scope and implementation

The owner's "please proceed" accepted the A6 recommendation to retain bounded
partial output, align deadlines and run one fresh comparison. The
[A7 brief](../soul/CONTINUITY_LAB_A7_BRIEF.md) defines that exact scope.

- `qwen_stream_response.rb`: bounded native SSE parser; 512 KiB wire, 64 KiB
  content and 2,048 data events per request. Handles split UTF-8/frames and
  bounded keepalive comments; rejects malformed, duplicate and post-final data.
- `qwen_transport.rb`: fixed loopback streaming completion, no proxy, redirect
  or retry. Timeout/disconnect retains fragments plus bounded incomplete-frame
  bytes and closes the connection. Partial transport output never becomes an
  action or a committed model response.
- `config.rb`, `qwen_broker_session.rb`, `sandbox_runner.rb` and the fixed worker:
  opt-in `qwen_stream_diagnostics_v1`, selected by v5 modes only. Legacy profiles
  keep their configuration digests and deadlines. Broker/worker/profile mismatch
  fails before execution. Full responses retain token-count/truncation checks
  and the unchanged strict action parser.
- `qualify-continuity-lab-qwen-a7.rb`: the same four A6 tasks and contracts,
  independent stores, expected-path sizing, observed-condition evidence and
  maximum 24 generations. No inserted expected action or answer, model-output
  repair, progress summary or forced next step.

Native stream semantics were checked against installed llama.cpp commit
`0eca4d490e591d4e93058d07540cf47278a72577` / b9851: text arrives in deltas,
final native content is empty, and native completion emits no `[DONE]` sentinel.
See the [pinned upstream server documentation](https://github.com/ggml-org/llama.cpp/blob/0eca4d490/tools/server/README.md)
and installed `tools/server/server-task.cpp` / `server-context.cpp`.

The experimental differences are explicit: streamed delivery and deadlines.
Model/build/template, v4 input protocol, guide, ordered grammar, sampling,
six calls, 768 output tokens, margin and resident 4K context remain unchanged.
Old A6 baseline hashes differ only in the five extended source files listed
above; the other 17 historical hashes match, including cases, actions and runtime.

| Bound | New diagnostic profile |
| --- | --- |
| Completion HTTP request | 60 seconds, also clamped to caller deadline |
| Other HTTP request | Existing 30-second ceiling |
| Event runtime | 420 seconds |
| Worker | At most 430 seconds; dispatch reserves 10 for final framing/cleanup |
| Batch | 1,800 seconds: work capped at 1,780, 20 reserved for cleanup |
| Final idle observation | At most 8 seconds, then at most 5 seconds settling; both clamped to remaining overall budget |

These are timeout/call bounds, not guarantees of throughput. In particular, all
six generations plus preparation must still fit the event/worker deadline.

## Deterministic and isolation evidence

Pinned Ruby: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.
Commands below are under `scripts/` and use prefix `verify-continuity-lab-`.

| Verifier suffix | Passing checks |
| --- | ---: |
| `core-a0.rb` | 21 |
| `recovery-a0.rb` | 149 |
| `context-a1.rb` | 30 |
| `recovery-a1.rb` | 94 |
| `admission-a2.rb` | 14 |
| `isolation-a2.rb` | 40 |
| `qwen-a3.rb` | 15 |
| `scoring-a4.rb` | 18 |
| `a4.rb` | 38 |
| `token-context-a5.rb` | 41 |
| `comparison-a6.rb` | 39 |
| `stream-a7.rb` | 40 |
| `stream-isolation-a7.rb` | 17 |

All **656 checks passed**; all 39 Continuity Ruby files passed syntax compilation.
The 17 new actual isolation/socket checks exercise both v5 modes, terminal
resume without generation, interrupted-stream worker reap, no partial effect,
unresolved-intent refusal and a real local HTTP socket stall/timeout/close.
They use synthetic responses, not inference. Fixed-route assertions remain in
place when the socket fixture maps traffic to its ephemeral local test port.

Luna provided read-only timeout mapping; Sol reviewed stream/harness safety and
test coverage. Review found the final read-back could exceed the initially
stated batch budget. Before inference, the harness gained an outer work timeout,
20-second cleanup reserve and remaining-budget clamps. Primary independently
inspected the authority boundaries and ran the integration checks.

All 15 historical A3–A6 stores reopened and validated with their original
configuration; every file hash was unchanged across that check. A6's interrupted
store still has its original 11-transaction head
`60c71536863cb90019a07c850f3f9d20d56309f07b43a73970d278f8de9c2dca`.
No historical store was resumed. The separate CLI preflight reported provider
reachability failure and warnings; that is not this desktop turn's permission
attestation. Exact supported host escalation was used for isolation/live checks.

## One fresh live window

Executed once, with no subsequent tuning, batch retry or journal resume:

```text
/home/bhones/.rbenv/versions/4.0.7/bin/ruby scripts/qualify-continuity-lab-qwen-a7.rb --approved-quiet-window
```

Private Git-ignored evidence:
`Soul/runtime/qualification/continuity-lab-a7-20261008T190820Z/`.
Finished 15:12:08 EDT after **227.596 seconds**. Four attempted/scored cases,
24 generation calls and 24 complete streams. No skipped, unstarted or unscored
case. Exit 1 reflects behavioral failure, not a transport/worker interruption.

Expected-path sizing passed for all four cases before inference:

| Task / condition | Input tokens at expected decision points 0–4 |
| --- | --- |
| Four reads / visible | 786, 1091, 1497, 2097, 2693 |
| Re-read / rollover | 787, 1107, 1523, 1813, 1717 |
| Four reads / rollover | 785, 1088, 1492, 1787, 1977 |
| Re-read / visible | 786, 1104, 1518, 2126, 2444 |

Each read requests 768 characters. Actual behavior:

| Case | Actual read starts / other response | Result |
| --- | --- | --- |
| Four reads / visible | 0, 768, 1536, invalid reply, 2304, 0 | Call-budget failure |
| Re-read / rollover | 0, 768, 1536, 0, 768, 0 | Call-budget failure |
| Four reads / rollover | 0, 768, 1536, 0, 2304, 768 | Call-budget failure |
| Re-read / visible | 0, 768, 1536, 0, 0, 0 | Call-budget failure |

**0/4 task passes; 0/4 qualified comparisons.** All four predefined visibility
conditions were observed, which is separate from task correctness. In particular,
the re-read/visible case retained every previous group through all six calls,
performed the four required reads, then repeated the initial read twice instead
of replying. Context omission is therefore not necessary for this failure.

### What the long response revealed

Four-reads/visible call index 3 had 2,124 input tokens and all three previous
results visible. It began a reply containing repeated `z` characters copied
from the filler, reached 768 output tokens and stopped with `stop_type=limit`
after **41.209 seconds**. The complete HTTP stream contained an unfinished JSON
string. The unchanged action parser rejected it as `invalid_action`; no reply
was accepted. Subsequent calls read the final span, then repeated span zero.
Group omission began only on the sixth call, after the initial deviation.

This distinguishes a **complete transport response** from a **valid action**.
Server `truncated=false` did not mean output generation reached a valid JSON
ending; the separate token-limit field and action parser expose that distinction.
The A6 response remains unknown: A7's similar path does not retroactively recover
or prove the contents of the earlier interrupted generation.

All other responses ended with EOS. Request durations ranged from 5.175 to
41.209 seconds, with 69–768 output tokens. The larger request bound allowed the
long response to return, but did not make the model complete the task.

## Integrity and cleanup

- All 24 assembled fragment streams match their recorded final content and
  token counts. All 24 journal contexts/preparations/responses match broker
  receipts, exact prompt hashes and submitted token-array hashes.
- All four new stores reopen, each with 20 transactions, one failed terminal
  event and zero notes. No unresolved intent remains in the new batch.
- All 23 A7 baseline source/grammar hashes still match. All 112 evidence paths
  are non-symlinked and owner-private; the root is Git-ignored.
- Immediate idle verification passed. Independent admission/observer read-back
  confirmed the same active service PID 3058, build b9851, 4K single idle slot,
  Core `amd-free`, profile `nvidia-fallback`, and no pending transition.
- Returned worker PIDs 178177, 179884, 180976 and 181833 are absent; no exact
  `/app/worker.rb` argv remains. An initial broad substring process check matched
  its own diagnostic command; exact argv/PID checking resolved that false alarm.
- Every sampled GTX 1070 allocation was 5,303/8,192 MiB; final utilization was
  0%. These are samples, not a certified peak-memory measurement. No model or
  service restart, GPU switch or persistence change occurred.

## Conclusion and next decision

The transport/timing repair is exercised and diagnostic evidence is now useful.
The model still fails to stop reading and produce the requested final answer,
including with complete visible history. This is not evidence that journal
recovery, token accounting or transport remains broken. It also does not qualify
long-horizon continuity or prove the model is incapable of it.

Recommended next step: a small, separately scoped diagnostic using meaningful
short passages instead of long single-character filler, retaining this batch as
the stress-test baseline. Use a full-visible control, then an exactly calibrated
rollover arm, with identical task contracts within each pair. Re-measure actual
tokens rather than assuming equal characters give equal token pressure. This
would test whether the artificial corpus is contributing to copying/looping;
it is a hypothesis, not a concluded cause or an unreported replacement test.

Do not simultaneously change prompt, sampler, model, memory semantics or add
an answer-producing controller. Further interface/stop-behavior changes should
follow that evidence. No new live window, dashboard or ordinary-memory activation
is authorized by this result. The completed approved window is closed.

The planning/debugging/evidence-review workflows kept historical failures intact,
made delivery/timing an explicit experimental condition, and kept infrastructure
success separate from behavioral and human acceptance.
