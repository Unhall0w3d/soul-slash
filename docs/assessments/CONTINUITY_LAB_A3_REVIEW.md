# Continuity Lab A3 original v1 qualification review

Historical first-run packet. The subsequent approved comparison is recorded in
the [A3 v2 review](CONTINUITY_LAB_A3_V2_REVIEW.md); the baseline below is unchanged.

Date: October 8, 2026 (America/New_York)
Candidate status: requires_repair / live requalification.
Implementation: fixed live adapter and harness implemented; deterministic checks pass.
Deployment/merge: not performed. Dashboard and experimental acceptance remain open.

## Authority and exact run

The owner approved the proposed maximum-20-minute, 20-case synthetic Qwen
window, with other clients kept idle and no service/model changes.
[A3 brief](../soul/CONTINUITY_LAB_A3_BRIEF.md) records the scoped adapter,
foreground lifecycle, evidence retention and budgets.

Executed once after a startup-only `Process.umask` typo was corrected to
`File.umask`. The failed startup attempt created no evidence directory and
contacted no model. The subsequent qualification completed at 00:42:18 EDT,
using 170.309 seconds of its 1,200-second budget and 42 of 60 allowed generation
calls. All 20 cases were scored; no infrastructure failure was recorded.
Harness exit 1 means behavioral expectations failed, not a server crash.

Retained owner-private, Git-ignored evidence:
`Soul/runtime/qualification/continuity-lab-a3-20261008T043928Z/`

- `baseline.json`: exact model/build/template metadata, on-disk hashes, config,
  sampling settings, case specifications and implementation hashes at execution.
- `calls.jsonl`: prepared intent and received raw result for each call, exact
  input envelope, rendered prompt, token IDs, usage, timing and digest binding.
- `case-1.json` through `case-20.json`: exact expectations' outcomes and receipts.
- `summary.json`: attempted/scored cases, returned worker receipts, failures,
  call budget, sampled GPU readings and final idle observation.
- `worker/store/`: replayable isolated synthetic journal. Independent reopening
  passed integrity with 157 transactions, 20 events, zero notes and head digest
  `18d2bc6ebd844463bf84e5a8d0ddaccdd4a772e481c07d17887a1a9172f5d846`.

No user private history, ordinary Soul memories or private corpus entered the
model. No upload, Git addition, cleanup or automatic retention policy was added.
Existing backups may include this local evidence directory.

## What is established

The same Qwen service/PID 3058 was running before and after. It remained on the
GTX 1070; no process load/unload, Core switch or service/network mutation occurred.
Core intent was `amd-free` (Soul-Lite), selected profile `nvidia-fallback`.
The installed API reported build `b9851-0eca4d490`, one idle slot and 4,096 context.
The corresponding inspected source checkout has matching commit prefix
`0eca4d490`; the live checks, not source alone, establish the exercised API.

The host broker successfully used the installed `/apply-template` and
`/tokenize`, verified the non-thinking suffix, then submitted those exact token
IDs to `/completion`. All 42 responses reported `tokens_evaluated` equal to the
submitted token count, and none reported truncation. The worker remained behind
the A2 pipe and Bubblewrap boundary; it received neither an arbitrary URL nor
host model/service access. Upstream route/tokenization semantics were checked
against [llama.cpp's server documentation](https://github.com/ggml-org/llama.cpp/blob/0eca4d490e591d4e93058d07540cf47278a72577/tools/server/README.md)
and the matching local source, then exercised on the installed endpoint.

| Observed metric | Result |
| --- | --- |
| Exact behavioral expectations | 7/20 met |
| Generation calls / generated tokens | 42 / 2,200 |
| Input tokens per call | 557–1,025; median 637.5 |
| Generation response time | 1.52–5.21 seconds; median 3.64 |
| Server-reported generation speed | 24.97–29.53 tokens/s; median 26.66 |
| Server-reported prompt ingestion | 430.66–484.56 tokens/s; median 466.23 |
| GPU allocation samples | 63 samples; 5,283–5,301 MiB of 8,192 MiB |
| Rejected malformed actions | 21 |
| Idle at end | verified; original service/PID independently rechecked |

These are synthetic workload measurements, not a general benchmark. GPU readings
are sampled allocations, not continuous peak-VRAM measurement. The final sample
was 5,301 MiB, 18 MiB above baseline; do not describe allocation as unchanged.
The configured context is 4K, but this run did not exercise near-full 4K input.

## Behavioral results and diagnosis

Passed cases: wait, exact Unicode reply, explicit corpus read, no automatic
corpus recall, no automatic history recall, simple arithmetic without notes,
and acknowledgement that an unavailable tool is unavailable. The corpus-read
case required one invalid action before a valid read, so its eventual pass does
not mean first-attempt reliability.

The dominant observed interface failure was a bare tool action, for example
`{"action":"note.write",...}` or `{"action":"read",...}`, instead of the required
`{"action":"tool","tool":"...","arguments":{...}}`. Runtime validation
rejected those outputs; it did not silently repair or execute them. In the
first reply case Qwen echoed the request rather than answering it. Some valid
tool envelopes repeated failed arguments until their bounded call budget ended.

The initial note was never created. Consequently cases 5–10 do not independently
measure a functioning note/read/update/tombstone chain. Their missing prerequisite
must not be counted as separate evidence that working storage failed. The
missing-source case replied `MISSING` but never completed a valid read: its text
alone therefore did not pass. The long multi-step case failed action syntax
before testing large retrieval or rollover. No context group was omitted.

This is evidence that the current prompt/adapter contract is not reliably
followed by this model under the recorded condition. It is not a result about
learning, consciousness, the value of persistent notes, or all Qwen capability.
Deterministic A0–A2 tests, not this model's replies, establish enforced safety.

## Prepared correction at the first handoff

After preserving the completed baseline, the broker prompt was versioned as
`qwen_envelope_v2_explicit_examples`. It explicitly locates the task in
`user.content`, distinguishes previous attempts from observed tool results,
shows parser-valid JSON envelopes, and tells the model not to repeat completed
actions or identical revision-conflicting writes. No validator was relaxed,
no response was rewritten, and JSON-object output constraints/settings remain
unchanged. New receipts and baselines identify the prompt version.

The v2 example shapes and forwarding contract pass deterministic checks.
At that handoff there had been no v2 live generation. The later
[v2 comparison](CONTINUITY_LAB_A3_V2_REVIEW.md) scored 13/20; this 7/20 baseline
must not be attributed to v2 or overwritten. The retained prompts and code
hashes identify the original v1 condition even though its receipt predates the
explicit prompt-version field.

The A1 packer still uses its named byte-based fixture counter. The live broker
adds an exact 3,072-token rejection gate plus 768 output/256 margin. It does not
silently trim groups or claim exact-token-optimal packing. Real-token overflow
retains an unresolved intent for review. Exact-token adaptive rollover remains
unqualified and may require a separately versioned context contract.

## Implementation and verification

New source: `qwen_transport.rb`, `qwen_host_observer.rb` and
`qwen_broker_session.rb` under `lib/soul_core/continuity_lab/`; explicit
`qwen_pipe` config/runtime and `qwen_run`/`qwen_resume` fixed worker modes.
The runner pairs the selected mode with the exact broker class and requires
admission. Transport pins loopback, denies redirects/proxies/fallback, bounds
request/response bytes and HTTP time, and accepts no model-selected route.
No ordinary Soul provider or shared lease semantics changed in A3.

New scripts: `qualify-continuity-lab-qwen-a3.rb` and
`verify-continuity-lab-qwen-a3.rb`. The A2 isolation verifier gained full-dispatch
timeout and broker/profile mismatch tests. Updated the A3 brief, adaptation
plan, canonical review gate and review template.

Commands use `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`:

| Verifier | Result |
| --- | --- |
| `verify-continuity-lab-core-a0.rb` | PASS 21 |
| `verify-continuity-lab-recovery-a0.rb` | PASS 149 |
| `verify-continuity-lab-context-a1.rb` | PASS 30 |
| `verify-continuity-lab-recovery-a1.rb` | PASS 94 |
| `verify-continuity-lab-admission-a2.rb` | PASS 14 |
| `verify-continuity-lab-isolation-a2.rb` | PASS 28 actual host-isolation checks, synthetic broker |
| `verify-continuity-lab-qwen-a3.rb` | PASS 15 fixture transport/contract checks, including v2 |
| `qualify-continuity-lab-qwen-a3.rb --approved-quiet-window` | Completed all 20; 7 behavioral passes; exit 1 |

Sol's focused review identified a synchronous broker-dispatch timeout gap. The
outer deadline now covers observation/receipts as well as HTTP, and a real
isolated-worker test exercises it. Summary bookkeeping now distinguishes a
returned worker receipt from scoring, preserving uncertain postprocessing.
A Ruby keyword-argument compatibility regression in the fake broker was caught
and repaired before the live run. No failed check is being reported as passing.

## Next action at the first handoff and continuing limits

The proposed second bounded synthetic window was subsequently approved and
completed in a new evidence directory with v2 and unchanged model/settings;
see the linked v2 review for results and the current next step. Continue to
separate prerequisite-dependent outcomes from independent capability scores.
Do not merge, deploy to ordinary chats, expose the dashboard lab or
declare Step 4 complete until note/retrieval/multi-step/rollover actually qualify.
The cooperative lock still cannot exclude a direct external client; the quiet
window remains an operator arrangement, not an enforced network boundary.
