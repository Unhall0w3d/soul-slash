# Continuity Lab A10 chronological-message comparison

Covered by the current A9 iterative authorization. A9 completed all four cases
with no infrastructure failure but no strict task passes. The visible-history
arm stopped after three reads with a literal "marker" answer; other arms repeated
reads. Meaningful passages alone did not fix the behavior.

Hypothesis: flattening previous assistant actions and tool results into one JSON
user turn obscures the conversational sequence for this small model. Test a
fixed host-side chronological projection using the installed template's native
assistant and tool roles. Its guide explicitly distinguishes attempted and
successful operations, repeated requested steps and terminal grounded replies.
This is a combined presentation/guide change, not proof of a single causal factor.

Pre-generation sizing revision: the initial native guide without JSON examples
made the reread history too small to trigger the predefined rollover boundary.
Restore the six generic action-shape examples already used by the legacy guide
for interface completeness; they contain no task answers or actual IDs. Freeze
this guide and repeat calibration before generating. Retain the rejected sizing
root (zero generations), rather than treating it as a behavioral failure.

## Bounds and invariants

Preserve A8's frozen fictional corpus, tasks, strict scoring, installed model,
grammar, sampling, output/call/context limits, A9 admission and fresh-store batch
bounds. Calibrate visible/rollover conditions before inference. If the new format
cannot establish the intended conditions, retain that result and revise the
comparison design transparently rather than scoring an unobserved condition.

The selected envelope and original action/result bytes remain journaled. The
projection is a fixed host formatting profile recorded in generation receipts,
code hashes and batch baseline; it does not change replay semantics or create
progress summaries, next-action hints, forced answers, notes or history. Retain
every included pair in order, including rejection results and original indices;
omit only whole oldest groups under the existing actual-token packing rule.
Escape angle brackets inside projected JSON to avoid treating source text as
template control tokens; parsed JSON values are unchanged.

No new worker capability, route, output repair, service/model change or memory
promotion. The host already attests prompt token counts; projection identity is
qualification evidence, not a new cryptographic trust claim.

## Verification

Test exact pair ordering, rejection retention, arbitrary task/Unicode content,
no mutation or invented progress, template-token escaping and default legacy
format preservation. Verify exact prepared-token reuse, receipt identity and
single-use generation. Run A5 token-context, A7 stream and actual isolation,
A8/A6 comparison and A4 scoring regressions. Preserve A9 evidence and validate
old stores and final idle state. A passing comparison is limited qualification,
not general long-horizon reliability, production activation or human acceptance.
