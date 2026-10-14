# Continuity Lab A13: practical receipt-retaining context

Date: October 8, 2026. Status: **receipt-retaining implementation complete;
four-case visible/rollover qualification passed on the chronological-pair profile**.
No production, dashboard, ordinary-memory, merge or release promotion.

## Authority and outcome

The owner approved the recommendation after prioritizing usability/usefulness
over reproducing the archive's minimal experimental condition. The
[A13 brief](../soul/CONTINUITY_LAB_A13_BRIEF.md) records that separate context
decision. A9's current iterative authorization permits evidence-led repairs and
fresh bounded trials; it does not permit resuming ambiguous historical intent,
rewriting a failed result, changing model/settings or enlarging model authority.

`Config.qwen_v6_qualification` opts into `current_event_receipts_v1`. Legacy
configuration digests and default behavior remain unchanged. The original
whole-group omission condition remains available for comparison. This is a
practical context adaptation, not a claim of model learning, consciousness,
calibrated inference or general continuity.

## Implemented contract

- When an old full action/result pair must be removed, retain an exact
  allowlisted projection of its recorded attempt, original index, outcome,
  failure reason and source identity/revision/digest/provenance/span.
- Drop bulky source text, search snippets and note-write contents. Retain the
  latest complete pair and current request. No generated summaries, inferred
  completion counters, suggested next actions or answers are inserted.
- Receipts are the ordered prefix, followed by the full suffix. The current
  six-call profile permits at most five previous pairs. There is no extra
  context allowance: the existing 12,288-byte and 2048/3072 input-token limits
  apply. Essential overflow rejects preparation before generation.
- Journal replay reconstructs the exact projection from committed state and
  binds receipt digests in the context manifest. Corrupted/reordered/forged
  receipts are rejected. Complete original evidence remains in the journal.
- Invalid actions retain their rejection and raw-response digest, not a made-up
  valid action. A compact note-write projection explicitly marks omitted content.
- Only current-event attempts enter this context policy. It grants no automatic
  cross-event recall, new history source, ordinary memory, permission or tool.
  A success receipt records execution, not understanding or task completion.

Two opt-in presentations are retained: `chronological_actions_v3_receipts`
places the records in the opening JSON envelope; `chronological_actions_v4_receipt_pairs`
renders those same records as historical assistant/tool pairs before recent
full pairs. Compact results carry `execution_receipt: true`. Note-write partial
actions have a `recorded_action` wrapper; invalid responses do not invent an
assistant tool action. Both escape angle brackets/control-token-like text.

## Changed paths

- `lib/soul_core/continuity_lab/config.rb`: explicit v6 receipt policy.
- `lib/soul_core/continuity_lab/receipt_context.rb`: bounded factual projection.
- `lib/soul_core/continuity_lab/context_builder.rb` and `token_context.rb`:
  shared byte/token trimming, manifest bindings and exact replay reconstruction.
- `lib/soul_core/continuity_lab/qwen_message_projection.rb`,
  `qwen_broker_session.rb`, `sandbox_runner.rb`, and
  `scripts/continuity-lab-worker.rb`: matching opt-in presentation/worker modes.
- `lib/soul_core/continuity_lab/qualification_cases_a13.rb`,
  `scripts/qualify-continuity-lab-qwen-a13.rb`, and
  `scripts/verify-continuity-lab-receipts-a13.rb`: unchanged strict A8 contracts
  with A12 clarified requests, calibration, live harness and deterministic tests.
- A13 brief/review, adaptation plan, human review gate and candidate template.

Other dirty/untracked work is preserved. No Git commit, merge or release.

## Deterministic and isolation evidence

Pinned Ruby: `/home/bhones/.rbenv/versions/4.0.7/bin/ruby`.
**713 distinct checks passed:** all 682 existing checks were rerun after the
core A13 change, plus 31 A13 checks. Repeated targeted runs are not added to the
count. After the second presentation was added, affected A5 token context,
A7 streaming, A10 projection/isolation and A13/isolation checks passed again.

| `scripts/verify-continuity-lab-*.rb` suffix | Checks |
| --- | ---: |
| core-a0 / recovery-a0 | 21 / 149 |
| context-a1 / recovery-a1 | 30 / 94 |
| admission-a2 / isolation-a2 | 14 / 40 |
| qwen-a3 / scoring-a4 / a4 | 15 / 18 / 38 |
| token-context-a5 / comparison-a6 | 41 / 39 |
| stream-a7 / stream-isolation-a7 | 40 / 17 |
| comparison-a8 / admission-a9 | 52 / 39 |
| message-projection-a10 `--isolation` | 23 |
| comparison-a12 | 12 |
| receipts-a13 `--isolation` | 31 |

The new verifier has 25 default checks and six actual isolated-worker checks
across the two receipt presentations. Coverage includes default compatibility,
exact allowlists, failure/note/search/malformed cases, ordered prefix/suffix,
omitted content, escaping, byte/token overflow without generation, forged
on-disk replay rejection even after recomputing a record hash, current-event
isolation, profile mismatch, unresolved intent, no-regeneration terminal resume
and child reaping. Synthetic isolation is not live model behavioral evidence.
Final syntax checks passed for 28 Ruby files; all 79 local documentation links
resolved. `git diff --check` and an explicit whitespace check covering the
new/untracked changed files passed.

Mapping was delegated to Luna Low and the new verifier to Luna High. Primary
owned the policy, implementation, live experiments, integration and boundary
review. No additional Sol review was completed; spawning one hit the agent limit.

## Live comparisons and retained failures

All roots are owner-private under `Soul/runtime/qualification/` and have prefix
`continuity-lab-`. Each live trial is capped at four cases, 24 generations and
1800 seconds, with fresh stores. Original model/build/template, non-thinking
mode, sampler/seed, grammar, output reserve, call limits and scoring are unchanged.

| Root suffix | Generations | Outcome |
| --- | ---: | --- |
| `a13-sizing-20261008T223400Z` | 0 | Reread essential context did not fit; rejected before inference |
| `a13-sizing-20261008T223727Z` | 0 | All four expected-path sizing/coverage contrasts passed after removing duplicated new-profile guidance |
| `a13-20261008T223838Z` | 10 | First visible task passed; reread rollover failed; two unstarted; 87.792 seconds |
| `a13-pairs-sizing-20261008T224830Z` | 0 | All four chronological-pair sizing/coverage contrasts passed |
| `a13-pairs-20261008T224937Z` | 20 | **4/4 strict task and intended-condition passes**; 168.904 seconds |

The first sizing failure was retained. Its partial failing measurements were
not individually persisted by that initial harness revision; subsequent revisions
write every calibration measurement immediately, explicitly labeled synthetic
expected-path data. They are never inserted into live worker journals.

In the first live trial, all four required reread operations succeeded. Decision
4 had receipts 0/1/2 plus full result 3, but Qwen requested another read at 768.
The following preparation rejected 2176 tokens, before a sixth generation. This
establishes that retaining receipts in the opening JSON was not sufficient on
that trial; it does not prove the model's internal reason. The second trial
changes their presentation, not their contents or a task-specific controller.

The successful fresh trial used `--approved-quiet-window --receipt-pairs`:

| Case | Successful read offsets | Final reply | Earlier full results omitted at final decision | Final input tokens |
| --- | --- | --- | --- | ---: |
| Four reads, visible | 0, 768, 1536, 2304 | `TEAL-42` | None | 2818 / 3072 |
| Required reread, rollover | 0, 768, 1536, 0 | `OPAL-19` | 0, 1, 2; corresponding receipts retained | 2027 / 2048 |
| Four reads, rollover | 0, 768, 1536, 2304 | `TEAL-42` | 0, 1, 2; corresponding receipts retained | 2028 / 2048 |
| Required reread, visible | 0, 768, 1536, 0 | `OPAL-19` | None | 2845 / 3072 |

Each case used exactly five model calls: four successful reads and one exact
reply, with no extra read, invalid action, repaired answer or truncated response.
In the rollover cases every omitted attempt remained accounted for by its
receipt. The newest full result carried the answer text. Both visible cases
retained all full pairs. Thus task success and actual visibility/receipt
conditions passed separately, rather than inferring rollover from calibration.

The forced 2048-token stress cases were close to their limit (20/21 tokens
remaining on their final inputs). This is not a robustness margin for arbitrary
tasks; essential overflow still terminates before generation. Random lineage
identifiers and generated JSON formatting can alter token counts despite fixed
sampler settings. The same seed does not make the two presentation trials a
perfectly controlled causal experiment. No further live retry was needed.

## Integrity and final read-back

- Independently reopened and integrity-validated **69 stores**, including all
  **20 new A13 stores**, without resuming events or generating new responses.
- All **1,261 pre-A13 files across 15 historical roots** retain the captured
  aggregate SHA-256 `ff47eb72acbf869c32af7703060df32217dca08b4d8413e458f3edaab2537b51`.
- Every A13 trial ended with idle verified. All six returned live workers have
  exited; synthetic worker reaping is also covered by isolation checks.
- Independent final host observation: unchanged PID 3058, Qwen3-8B-Q4_K_M,
  nvidia-fallback profile, amd-free core, b9851-0eca4d490, context 4096,
  one slot/zero active slots, no pending transition. The successful trial sampled
  5303/8192 MiB on the GTX 1070 throughout. No service/model switch occurred.
- All 28 latest baseline implementation/harness hashes match the files under
  review; all 241 A13 evidence paths checked are owner-private and non-symlinks.

## Limits and next gate

This is current-event, bounded synthetic task evidence. Optional note lifecycle,
fresh-worker retrieval and cross-event continuity must be qualified on this new
profile before treating earlier-profile successes as transferable. The small
single-seed comparison does not estimate a general reliability rate or isolate
all causal effects of presentation, quantization, hardware or model capability.

No new service, watcher, schedule, background inference, model switch, ordinary
memory write, private-data transfer, package, network or power change occurred.
Human implementation authorization is recorded; integration/deployment,
merge/release and user-facing acceptance remain separate.
