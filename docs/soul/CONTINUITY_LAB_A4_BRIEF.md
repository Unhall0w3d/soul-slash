# Continuity Lab A4 focused interface and qualification repair

Status: owner approved "let's continue as you've outlined" on October 8, 2026,
after the A3 v2 review proposed scoring, structural actions, bounded failure
handling and focused correction/deletion/rollover tests. This records that
scope; it grants no dashboard, release, merge or ordinary-memory authority.

## Implementation plan and ownership

1. Add a pure result-bound qualification scorer and deterministic negative
   fixtures. Bind expected actions to successful targets, lineage, revisions,
   spans, text and sequence; distinguish unmet prerequisites. Primary owns the
   harness and integration; a bounded worker may own only scorer/test files.
2. Version the Qwen interface as v3 with a structural action JSON schema and
   complete examples. Keep raw responses unchanged, the parser authoritative,
   and existing sampling/non-thinking/4K limits. Preserve the historical v1/v2
   receipts and legacy profiles. Structural constraints are a recorded change,
   not a semantic repair or expansion of tools.
3. Add an opt-in, configuration-bound repeated-failure policy. After two
   consecutive equivalent parsed tool actions both fail with the same reason,
   terminate failed/repeated_failed_action before another generation. Preserve
   both results, original notes, replay validation and crash/recovery behavior.
   Never treat an unsuccessful action as a successful reply or rewrite its ID.
4. Add independent synthetic correction and tombstone prerequisites, retain a
   short end-to-end note chain, and force omitted-context/re-read qualification
   with an explicitly smaller fixture packing budget (not a claim to test the
   full resident context). Verify omission deterministically before live use.

Primary owns config, runtime/journal policy, broker, worker isolation, admission,
fixtures, live execution and review. Preserve all unrelated dirty paths. No
commit, upload, deletion or model/service/network mutation.

## Foreground live scope and retention

One new focused batch only: maximum 20 cases, 60 generations total, 6 per case,
1,200 seconds total, 60 seconds per worker, 30 seconds per generation, output
768 and actual input ceiling 3,072 tokens. Same resident Qwen/model/server
hashes, sampler, idle admission and operator quiet-window arrangement as A3.
No live tuning/reruns within this authorization. Stop on uncertain/busy/drifting
runtime or infrastructure failure; preserve behavioral failures as measured.
Keep other Qwen clients idle; cooperative locking does not exclude them.

Retain all raw inputs, code/contract/config hashes, synthetic setup receipts,
tool results and summaries in a new private Git-ignored
`Soul/runtime/qualification/continuity-lab-a4-<timestamp>` directory. No ordinary
Soul data. Close transport/reap workers on exit; no continuation or services.
Unresolved model intent stays blocked for human review without automatic retry.

## Required evidence

Run A0 core/recovery, A1 context/recovery, A2 admission and actual isolation,
A3 transport checks, plus new scorer and repeated-failure/recovery fixtures.
Prove legacy journal/config compatibility, failed-policy terminal validation,
resume idempotency, recovery after interruption, changed-argument recovery,
no false stop on successful reads and no false scoring from wrong targets or
missing prerequisites. Check schema grammar conversion against the matching
local llama.cpp source before live use without generating model output; actual
resident-server acceptance is measured by the first governed generation.
Record changes in condition; no direct
pass-rate comparison of different test catalogs as a model-quality statistic.

Update the adaptation plan, canonical review gate and review template after
actual results. Candidate implementation, live capability, safety enforcement,
and later human experiment acceptance remain separate evidence levels.

## Executed window and prepared follow-up

The single focused batch ended October 8 at 02:30:01 EDT after 17 generations:
4 passes, 2 behavioral failures, 5 prerequisite skips, one interrupted case and
one unstarted case. The actual-token guard rejected the next generation at
3,278 input tokens. Raw evidence is retained separately; no rerun occurred.

Post-run diagnosis identified canonicalized schema property ordering and
duplicated prompt protocol text. The v3.1 candidate uses a fixed ordered grammar
and removes the duplicate wrapper text. Deterministic checks pass; tokenizing
the same rejected envelope now yields 3,045 tokens without any generation.
See the [A4 review](../assessments/CONTINUITY_LAB_A4_REVIEW.md). Live v3.1
acceptance and dashboard integration remain open; another batch requires a new
bounded window, not automatic continuation of the failed one.

## Approved fresh v3.1 window — October 8, 2026

The owner's "alright, let's continue please" authorizes the proposed one fresh
v3.1 batch. The same foreground limits, unchanged model/sampler, synthetic-only
data, quiet-window arrangement and retention rules above apply. This is a new
evidence root, not a retry/resume of the interrupted v3 event. Stop on admission
drift or infrastructure failure; no automatic live tuning or second batch.
Dashboard integration, ordinary-memory activation, merge and release stay held.

This fresh window ended at 13:46:37 EDT: 11 completed cases passed, case 12 was
interrupted at 3,774 actual input tokens, and case 13 was not started. Evidence
and proposed next work are in the [v3.1 review](../assessments/CONTINUITY_LAB_A4_V3_1_REVIEW.md).
The authorized window is finished; no automatic retry or journal resume.
