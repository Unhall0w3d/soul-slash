# Continuity A19: chronological chat projection

Date: 2026-10-12. The owner's "approved, please continue" accepts the A18
recommendation: implement chronological chat presentation and run one bounded
comparison if the unchanged model/build is available. No deployment, model or
service restart, ordinary memory, network change or autonomous continuation.

## Exact intervention

Keep A18's v9 config, journal, recent-exchange selection, corpus, one-call/zero-tool
limits, grammar, token preparation, sampler and model unchanged. Add a separately
named direct-chat message projection and exact fixed worker run/resume modes.
The existing v9 mode must continue to require the original direct projection;
the new mode must require the new projection. Both enforce all direct-evidence
guards. Primary owns projection, broker/worker bindings, runner and live use.

Present selected earlier exchanges as alternating user/assistant messages in
journal order, then the current user request last. Preserve exact utterance text
apart from existing template-control escaping. Keep the same system/protocol
text. Complete sources and ordered provenance metadata remain a labeled reference
data block attached to the first user message, never promoted to system authority.
Prior transcript text is represented once in its corresponding role messages;
its IDs/revisions/digests/spans remain in reference metadata and the original
replayable envelope. No inferred summary, corrected answer or synthetic assistant
acknowledgement is inserted. Empty history and empty corpus must work.

Acceptance: exact chronological roles and current request last; content/provenance
preservation; template-token escaping; unchanged original projection/config;
same full-corpus and whole-oldest-dialogue eviction and essential-overflow refusal;
one-call/reply-only enforcement; wrong-profile refusal for old and new workers;
actual isolated synthetic run/resume; targeted shared-boundary regressions and
replay of every historical store. Preserve prechange copies and prior evidence.
Delegate only new pure cases/verifier work. No existing scorer tuning.

## Frozen foreground comparison

Compare fresh A18 direct-envelope baseline with direct chronological chat. Use
the same 24 A18 cases and four separately frozen new cases: a new constrained
selection, two successive corrections, then a callback. Seven independent stores
per condition, fresh worker per event; alternate condition order by batch.
Freeze case packs, oracle checks, scorer, runtime, source hashes and order before
generation. Each condition receives the same selected source corpus; histories
can diverge through model replies. This is a conversation-presentation comparison,
not identical tokens, repeated statistical sampling or model-server continuity.

Maximum 56 scheduled requests / 56 generations, 900 seconds including a twenty-
second cleanup reserve. Same Qwen3-8B-Q4_K_M and installed model/build digests,
4096 context / 3072 input / 768 output reserve, thinking disabled. Observe and pin
the currently running service PID in the new runner; prior PID is dated evidence,
not permission to start or replace a process. Busy/incompatible runtime blocks
live execution without eviction. Preserve first failures; no live retry, tuning,
scorer repair, second window or worker surviving the turn. Infrastructure or
evidence failure stops the suite; behavioral failures remain results.

## Closeout

Score factual/source-supported accuracy, successive correction/callbacks,
unknown-fact grounding, social quality, calls/tokens/time and completion
separately. Preserve frozen screen scores and explain semantic discrepancies in
a separate primary assessment. Do not claim safety from model replies or general
reliability from this pilot. Update A19 review, adaptation plan and canonical
human/candidate review links. Further adaptation/promotion is a separate decision.
