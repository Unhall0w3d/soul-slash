# Continuity Lab A5 actual-token context preparation

Owner approval: "okay, please proceed" after the A4 v3.1 review proposed real
tokenizer packing and a new focused qualification. No dashboard, ordinary-memory,
merge, release, model switch or service mutation is authorized.

## Implementation and ownership

Primary owns the versioned context, journal, pipe/broker and isolation contracts.
Retain all legacy profiles and journals unchanged. A new opt-in Qwen profile
prepares context before committing model intent. The host's existing fixed
formatter/tokenizer measures the complete prompt; remove only whole oldest tool
groups until it fits. Never drop instructions, the current request or newest
result. Keep the exact selected input, count evidence, version and omission
manifest in the journal; verify its structure against eligible state on replay.
Generation must consume that same host-prepared input/token array exactly once.
Disconnect before intent has no generation; unresolved intent after commit still
blocks automatic regeneration. Essential overflow fails closed with receipts.

The broker remains fixed loopback, foreground and bounded. No arbitrary URLs,
runtime selection, new HTTP routes, semantic action repair or synthetic progress
summary. Same ordered grammar, prompt instructions, sampler, 768 output reserve,
256 margin and 4K resident context. Normal actual input ceiling stays 3072;
the explicit rollover fixture uses 2048 actual input tokens, not a resident
context change. Initial byte-bounding protects the existing pipe limit only;
the installed tokenizer makes the final inclusion decision within that cap.
The existing broker input cap is 12,288 bytes (smaller than the framing cap).
Byte trimming can conservatively omit highly compressible text that might fit
the token budget; record `input_byte_limit` separately from `actual_input_budget`.
This preserves the existing resource bound, not a maximum-context-utilization
claim. Essential byte or token overflow must commit a grounded failed terminal;
interrupted token rejection commits are replayed without inference.

## Checks and one live window

Add deterministic tests for trimming/essential preservation, exact prompt/token
binding, stale/changed preparation, sequence/size bounds, pre/post-intent faults,
replay and legacy compatibility. Run A0/A1 recovery, A2 admission and actual
isolation, A3 transport, A4 scoring/policy plus the new A5 tests. Reuse unchanged
grammar conversion evidence; the grammar and sampler must remain identical.
Inspect retained prompts offline; optional formatter/tokenizer-only checks may
validate sizing without generation before the one live batch.

One fresh synthetic batch: the seven-case note lifecycle regression, four reads
plus terminal reply, and omitted-context re-read. Maximum 9 cases, 54 generations,
6 generations per case, 1200 seconds overall, 60 seconds per worker and 30 seconds
per HTTP request. Keep other Qwen clients idle; cooperative admission does not
exclude external clients. Same model/server/template identity and resident PID;
stop for drift, busy admission or infrastructure failure. No silent live tuning,
second batch, or resumption of earlier interrupted journals.

Use a new private Git-ignored `Soul/runtime/qualification/continuity-lab-a5-*`
root. Retain raw preparations/generations, source hashes, manifests and results.
Reap workers, verify idle/runtime identity and update the canonical review gate,
template and adaptation plan. Model behavior is usefulness evidence, not safety
authority. Complete scoring, an interrupted case and unstarted cases stay distinct.

## Executed window

The one batch ended October 8 at 14:16:01 EDT. Actual-token packing stayed within
bounds across 25 generations; seven cases passed and two ended in the model-call
budget after repeated reads without a final reply. All nine were scored; there
was no infrastructure interruption. See the [A5 review](../assessments/CONTINUITY_LAB_A5_REVIEW.md).
No automatic rerun, prompt tuning or dashboard activation follows this window.
