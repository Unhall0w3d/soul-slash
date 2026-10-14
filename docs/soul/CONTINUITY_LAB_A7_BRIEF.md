# Continuity Lab A7 bounded streaming diagnostics

Owner authorization: "please proceed" after the A6 review proposed bounded
partial-output retention, consistent time budgets and a fresh comparison.
Primary owns transport, journal/runtime contracts, host execution and evidence.
Luna maps timeout paths read-only; a scoped static reviewer may critique changes.

## Exact scope

Add an opt-in `qwen_stream_diagnostics_v1` execution profile, selected only by
new fixed v5 worker modes. Keep old configuration digests/defaults and old
journals intact. Keep v4 input protocol/token preparation, A6 paired tasks,
model/build/template, prompt guide, grammar, sampling, six calls, resident 4K,
768 output tokens and margin unchanged. Only delivery becomes streamed and
time limits change; record both differences as an explicit condition.

Use fixed loopback `/completion`, no proxy/redirect/retry or arbitrary endpoint.
Parse the installed b9851 native SSE protocol, not an OpenAI chat schema.
Bound total wire bytes, frame count and accumulated content. Retain incremental
decoded fragments in owner-private diagnostic receipts; an incomplete trailing
frame may be retained as bounded encoded bytes. Partial output never becomes
a model response or action. Require terminal metadata, exact input count,
bounded output count, no truncation, and complete transport framing before
returning a response. Timeout/disconnect/invalid stream closes the connection,
retains diagnostics and leaves unresolved intent without regeneration.
Trailing blank lines/SSE keepalive comments are allowed within the wire cap;
any post-terminal data event is rejected. They never contribute model content.

Completion requests: at most 60 seconds and the caller's absolute deadline.
Other HTTP routes: existing 30-second limit. New event runtime: 420 seconds;
worker wall deadline: at most 430 seconds (includes host callbacks/reaping);
legacy profiles stay at 60 seconds. Six worst-case generation calls consume
360 seconds, leaving bounded preparation/coordination headroom. This is not
a throughput guarantee; the absolute event/worker limits still win. One batch
has four cases, at most 24 generations and 1800 seconds overall: work is bounded
to 1780 seconds, reserving 20 for cancellation and final read-back. The initial
idle check is capped at eight seconds and settling at five, each also clamped
to the remaining overall budget. Stop on the
first infrastructure interruption; no live tuning or second batch.

## Implementation and checks

Owned paths: continuity_lab streaming parser/transport, opt-in config and
broker/runner/worker routing; A7 verifier and harness; review/plan documents.
No service/model change, scheduler, dashboard, ordinary memory, merge or release.

- Deterministic parser/transport checks: split frames and UTF-8, final metadata,
  duplicate/trailing/malformed frames, EOF, stall/timeout, size/count caps,
  callback failure, route/retry/proxy restrictions, partial retention and no
  partial execution. Verify new timing propagation and legacy rejection.
- Existing A0/A1 recovery, A2 admission/isolation, A3 transport, A4 scoring/policy,
  A5 token context and A6 comparison checks. Actual isolated-worker checks with
  a synthetic stream must cover both v5 profiles, terminal resume, interruption
  cleanup and unresolved-intent refusal. No real model in deterministic checks.
- Check pinned upstream source/stream shape before implementation; no model
  request merely to discover protocol. Preserve all historical stores and their
  head digests; do not resume them.
- Fresh approved live batch uses A6's four tasks and expected-path sizing in a
  new private Git-ignored `Soul/runtime/qualification/continuity-lab-a7-*` root.
  Retain source hashes, settings, prompts, streaming fragments, final metadata,
  results and errors. Independently check idle/service identity and worker reap.
  A bounded read-only cancellation-settle check may last five seconds; it may
  not kill/restart the resident model or silently regenerate work.
- Update the canonical review gates. Keep task score, condition observation,
  transport completion and human acceptance distinct. This window grants no
  permission to repair prompts, add progress summaries or broaden capabilities.
