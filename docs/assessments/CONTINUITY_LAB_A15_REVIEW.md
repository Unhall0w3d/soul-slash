# Continuity Lab A15: foreground usability and conversation

Date: October 8, 2026 (evidence timestamps are October 9 UTC).
Status: **assessment complete; everyday usability target not met**.
No runtime, model, ordinary-memory, dashboard or release promotion.

## Scope and method

The owner authorized a foreground usability assessment and explicitly added
generic conversation. The [A15 brief](../soul/CONTINUITY_LAB_A15_BRIEF.md) fixed
three independent four-event batches before inference: planning, held-out
practical tasks and casual conversation. Requests named goals, not exact tool
sequences or note operations. All figures and conversation utterances are
synthetic; none is an ordinary-memory fact about the owner.

The A13 runtime/guide/model/sampler stayed frozen. A14 is a historical reference
for directed execution, not a matched control for these different tasks. Each
turn used a new worker and an empty initial context except for protocol and the
current request. Earlier exchanges were available through history retrieval,
not automatically supplied. The model server stayed running. This is the
current lab's retrieval-dependent behavior, not an ordinary recent-history chat
control, a model-server restart test or evidence about all Qwen configurations.

No prompt, case, corpus or scorer was tuned after observing model results.
Failed live cases were not retried. Mechanical checks are necessary screens,
not semantic judges; primary reviewed every reply and tool trace separately.
The three introductory conversation turns were explicitly semantic-review cases.
No subagent or model output grants human acceptance or promotion authority.

## Results

Roots are under `Soul/runtime/qualification/`.

| Batch/root | Completed replies | Mechanical screening | Calls | Elapsed |
| --- | ---: | ---: | ---: | ---: |
| `continuity-lab-a15-planning-20261009T021109Z` | 4/4 | 0/4 eligible | 10 | 66.098 s |
| `continuity-lab-a15-holdout-20261009T021313Z` | 4/4 | 1/4 eligible | 9 | 60.789 s |
| `continuity-lab-a15-conversation-20261009T021500Z` | 4/4 | 3/4 eligible | 6 | 44.030 s |

All 12 reached a reply terminal in 25 generations; none was interrupted, skipped,
invalid JSON, out of budget or subject to context eviction. Completing a reply
is not completing the user's task. The 4/12 mechanical figure is **not** an
overall success rate: three are semantic-only conversation screens, and the
unknown-delivery answer was a declared-pattern false negative described below.

### Primary assessment against the fixed tasks

| Case | Assessment | Evidence |
| --- | --- | --- |
| `m-plan` | Task failed | No projector or price; one over-specific empty corpus search, then asked the user to refine it. |
| `m-change` | Task failed | Did not calculate two Cedar units at 55 credits each; empty search, then guessed a nonexistent note ID. |
| `m-recall` | Continuity failed | Did not recover the user's recorded Cedar/two decision; searched corpus and guessed a note rather than searching history. |
| `m-unknown` | Appropriate narrow abstention | Accurately said its search found no delivery-time information; invented no confirmation/time. This does not prove exhaustive absence. |
| `c-uppercase` | Passed | Exact `BRING THE BLUE NOTEBOOK`, one call, no unnecessary tools. |
| `c-plan` | Task failed | Did not calculate three Meadow bags / 27 credits; empty full-phrase search and request for more details. |
| `c-change` | Task failed | Did not calculate four Birch bags / 32 litres / 24 credits; guessed note ID, then searched plural `Birch bags` against singular `bag`. |
| `c-recall` | Continuity failed | Did not recover the user's recorded four-Birch decision; guessed note ID and searched corpus rather than history. |
| `chat-walk` | Adequate standalone greeting | Polite, acknowledged the walk and tea supplied in the current request; generic assistant-style closing. |
| `chat-reason` | Relevant but weak follow-up | Acknowledged needing a break but used a generic closing rather than developing the conversation. No earlier-turn retrieval. |
| `chat-drink` | Partial / pragmatic error | Acknowledged hot chocolate, but said it would replace the tea for the speaker, although the speaker had already done so. No tool/action actually performed. |
| `chat-recall` | Continuity failed | Could not recover the drink or reason for the walk; searched the empty corpus using the whole question, then read a nonexistent note. Never searched history. |

These labels are primary assessment, not the owner's human acceptance. All six
source-dependent practical questions failed, and the conversation callback
failed. No self-authored note was created in any batch. That is an observation,
not a failure criterion: the existing history already contained the callbacks'
user decisions, and notes were optional.

### Conversation transcript

**User:** Good evening. I've just got back from a long walk and finally sat down
with some tea. How's it going?

**Qwen:** Good evening! It's lovely that you've had a long walk and are now
enjoying some tea. I'm here and ready to assist you with whatever you need!

**User:** It was mostly to clear my head. Nothing dramatic; I just needed a break.

**Qwen:** Understood. It's important to take breaks when needed. Let me know if
there's anything else I can assist with.

**User:** By the way, the tea was a mistake—I've swapped it for hot chocolate.

**Qwen:** Got it! I'll make sure to replace the tea with hot chocolate for you.
Enjoy your hot chocolate!

**User:** What am I drinking now, and what got me out of the house earlier?

**Qwen:** I couldn't find the information about what you're drinking now or what
got you out of the house earlier. Please provide more context or check if the
information is available elsewhere.

This is polite single-turn fluency, not convincing conversational continuity.
The drink response overstates the assistant's role; it is not a claim that a
note write or physical action actually occurred. Runtime records contain none.

## Mechanism and limits of the diagnosis

The 13 retrieval attempts were eight empty searches and five `not_found` reads;
none returned source content. All tool results agree with deterministic replay.
There were no history searches or reads. The highest measured input was 1,059
tokens, with no omitted groups, transport failure or resource exhaustion. These
failures therefore were not caused by observed context rollover or a lost journal.
The pilot cannot isolate model capacity from tool/interface design.

The lexical implementation requires **every query word** to appear exactly as
a case-folded word; it does not stem plurals. The protocol declares a query
string but does not explain that AND/exact-word behavior. Examples from the run:

- `projector with HDMI and battery power rental catalog` returned no hit. The
  rental text did not contain `projector` or `with`, despite containing the
  relevant options, HDMI, batteries and prices.
- `Copperfield garden supply list Meadow bags` returned no hit; the source
  used `bag`, not `bags`.
- The final conversation question was used verbatim against `corpus`, which
  was empty for that batch, then the event ID `chat-recall` was treated as a
  note ID. The needed exchanges were in `history`.

Independent read-only calls to the same Retrieval function, outside model
events, verified `Marigold` and `Cedar` retrieve the existing rental source;
history queries `chocolate` and `head` retrieve the beverage change and reason
for the walk. These diagnostics did not feed hints to the model or write events.
They establish content availability and the narrow query failure, not that a
changed prompt/tool would make Qwen choose those queries reliably.

Qwen also failed to broaden searches and guessed logical IDs after no hit.
The interface is brittle and the model did not compensate for it. This does not
justify attributing everything to insufficient VRAM or claiming a larger model
is necessary. Nor do accurate no-result reports make a failed available-data
task useful: several replies unnecessarily pushed the repair burden onto the user.

The fixed uncertainty regex omitted the valid phrase `did not find any
information`. Thus `m-unknown` failed the mechanical phrase check but passed
primary review as narrow, accurate abstention. The frozen score was not changed.
Conversely, the conversation's first three mechanical passes establish only
well-formed, nonempty replies; the transcript contains a qualitative shortcoming
and a pragmatic error. These distinctions are why both evidence levels remain.

## Validation, repairs and resource measurements

New qualification-only files:

- `lib/soul_core/continuity_lab/qualification_cases_a15.rb`
- `scripts/qualify-continuity-lab-qwen-a15.rb`
- `scripts/verify-continuity-lab-usability-a15.rb`
- A15 brief/review and canonical plan/review links.

Pinned Ruby 4.0.7: syntax checks pass; the new verifier passes **eight grouped
checks** (seven synthetic groups covering all 12 events, plus one actual-isolation
group with two representative workers). Coverage includes alternate grounded
search/read routes, optional and absent notes, prior-note support, exact effect
replay, malformed/fabricated evidence, unsupported and stale replies, clean initial
contexts and distinction between mechanical and semantic assessment. The frozen
runtime's previously passing checks remain applicable; they were not repeated.

The first synthetic isolation attempt exposed a verifier setup error: an existing
store was accompanied by a nonempty corpus in its request. The verifier was fixed
to send an empty corpus, corrected its PID check, and passed before inference.
The first live preflight (`continuity-lab-a15-planning-20261009T020955Z`) then
exposed a missing explicit Store import in the new runner. It stopped with zero
generations/workers. That attempt is retained; adding the import did not change
the runtime, prompts, corpus or scoring. All subsequent model trials were first
attempts on those unchanged prompts. No behavior-driven tuning occurred.

The successful-infrastructure batches used 170.917 seconds of total harness
wall time, including model/build hashing and validation. Completed stream receipts
report 1,722 generated tokens and 22,161 evaluated prompt tokens across 25 calls;
repeated instructions/history are counted per call, not unique tokens. The
preflight-only failed attempt adds 17.258 seconds and zero model tokens. These
are local model measurements, not Codex subscription usage or a controlled speed
comparison. All 12 live workers exited; each batch verified idle resident inference.

All **76 stores** pass integrity without resuming events. The frozen 28 A13 code
hashes and all three generative A15 trial code hashes match current files. All
24 pre-A15 evidence roots / 1,623 files are unchanged; sorted path/content-hash
aggregate remains:
`9213001bb7ceb081c7b1cff5566c816bf077cb14f9c930cf6b97a7a1646be33b`.

## Recommendation: two separate next experiments, not implemented

1. **Repair the tool-interface mismatch first.** Explicitly describe keyword AND
   semantics, collection choice (history for conversations), and discovering IDs
   from hits rather than guessing. Test against untouched task wording plus new
   cases. If that is insufficient, separately evaluate deterministic broader
   lexical matching/ranking; do not silently combine both interventions or inject
   expected answers. No embeddings, new model or new service is required merely
   to test these hypotheses.
2. **Give practical conversation a bounded recent-exchange window.** Treat recent
   observed dialogue as a distinct context source with provenance and tokenizer
   accounting; keep long-term notes optional and runtime receipts separate.
   Preserve the original minimal/retrieval-only condition. This is a new context
   policy choice requiring its own scoped brief, not a claim that it has passed.

Do not promote the current profile as ready for everyday conversational continuity.
Retain the working durable execution/retrieval foundation. The next measure should
be whether it finds relevant evidence and carries on a normal conversation with
less operator repair—not whether increasingly explicit scripts can force success.
