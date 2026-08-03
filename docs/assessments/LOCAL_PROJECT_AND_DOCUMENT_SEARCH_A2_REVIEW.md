# Local Project and Document Search A2 Review

Status: accepted and merged through PR #28 on 2026-07-27

## Implementation

A2 preserves deterministic retrieval while making its Chat behavior useful
across both production chat Cores.

- General multi-source searches retain one qualifying result from every
  contributing adapter when the requested limit can accommodate them.
- Chat accepts explicit repository, Knowledge Vault, Music, and Visual search
  phrases.
- Results are numbered in deterministic rank order.
- An explicit follow-up about the immediately preceding search result receives
  direct model synthesis rather than being stolen by another skill router.
- Local-search history is declared untrusted and reference-only in the model
  context.
- Authority inversion, token-limit completion, and structurally incomplete
  requested lists receive at most one foreground retry.
- Repeat failure returns the original deterministic evidence and a
  non-authorizing disclosure.
- A manual cross-Core evaluator refuses to switch Cores, requires an idle
  conflict-free runtime, and stores chats and request receipts only below a
  temporary directory.

## Files changed

- `Makefile`
- `config/invocation_catalog.yaml`
- `config/project_tracker_seed.json`
- `docs/ARCHITECTURE.md`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/ROADMAP.md`
- `docs/assessments/LOCAL_PROJECT_AND_DOCUMENT_SEARCH_A2_REVIEW.md`
- `docs/guides/LOCAL_SEARCH.md`
- `docs/soul/LOCAL_PROJECT_AND_DOCUMENT_SEARCH_A2_BRIEF.md`
- `lib/soul_core/conversation_context_builder.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `lib/soul_core/conversation_runtime.rb`
- `lib/soul_core/local_search_chat_controls.rb`
- `lib/soul_core/local_search_service.rb`
- `scripts/run-local-search-cross-core-eval.rb`
- `scripts/verify-local-search-a2.rb`

The ignored owner-local Project Timeline is updated separately through
`ProjectTrackerService`.

## Commands run

```sh
ruby scripts/verify-local-search-a1.rb
ruby scripts/verify-local-search-a2.rb
make verify-local-search
ruby scripts/verify-chat-intent-and-interaction-boundary.rb
ruby scripts/verify-responsive-chat-and-web-research.rb
ruby scripts/verify-conversational-creative-workflow.rb
ruby scripts/run-local-search-cross-core-eval.rb amd-free
ruby scripts/run-local-search-cross-core-eval.rb daily
git diff --check
```

Core transitions used the existing preview, digest, exact-confirmation, active
work, and conflict gates. The evaluator itself performed no Core transition.
Music Core was restored after evaluation.

## Deterministic results

All A1 and A2 checks pass. A2 covers:

- balanced multi-source selection;
- exact single-source behavior;
- all four source-scoped Chat forms;
- ordinary-conversation and public-web routing restraint;
- broader authority-inversion detection;
- one bounded corrective retry;
- deterministic repeat-failure fallback;
- token-limit and structurally incomplete response handling;
- local-search follow-up priority over a competing creative-archive route;
- untrusted/reference-only model context;
- absence of resident, scheduled, or network search behavior.

The existing Chat intent, responsive Chat/web research, and conversational
creative-workflow suites also pass.

## Local LLM evaluation

The matched harness ran four real search/follow-up conversations per Core:

1. Knowledge Vault Core topology;
2. ranked liquid drum-and-bass Music projects;
3. the Backrooms Visual project;
4. repository confirmation-gate authority.

Final results:

| Core | Profile | Score | Result |
| --- | --- | ---: | --- |
| AMD-Free | Qwen3 8B Q4_K_M / NVIDIA | 15/15 | pass |
| Daily | Gemma 4 12B Instruct Q4_K_M / AMD | 15/15 | pass |

Both models named the exact Core topology, the same first two Music projects,
and the same Visual project with grounded scene details.

Gemma answered the authority case directly. Qwen ultimately returned the
deterministic local-search fallback after its model path produced unusable
text; the fallback preserved the requested digest/confirmation evidence and
explicitly stated that the evidence authorized no action. This is comparable
factual coverage with intentionally different fail-safe presentation, not a
claim that the models have identical behavior or latency.

## Failures encountered

The first pre-A2 comparison demonstrated that a one-query smoke test was
insufficient:

- unrestricted end-to-end Gemma scored 12/17 and Qwen 6/17;
- repository documents hid canonical Music records;
- Qwen truncated a Core answer and inverted the authority boundary;
- a Visual follow-up could route to the creative archive instead of the
  preceding local-search result.

The first live A2 Qwen run improved to 10/15 but exposed two remaining defects:
the Visual route collision and a positive authorization sentence containing an
intervening document reference. Both received deterministic fixes and
regression coverage before the final 15/15 rerun.

## Memory, mutation, and lifecycle

- Shared memory read/write: none.
- Knowledge Vault: bounded read only.
- Studio projects: bounded canonical brief read only.
- Repository: reviewed Markdown read only.
- Evaluation persistence: none; temporary Chat and receipt state only.
- Automatic Core switching: none.
- Search lifecycle: `complete`, `awaiting_input`, or `failed`.
- Follow-up lifecycle: `complete` or deterministic
  `local_search_grounding_fallback`.
- Mutation: none.
- Risk: Class 0, read-only local-private evidence.

## Known weaknesses

- lexical search still does not understand synonyms or semantic similarity;
- balanced ranking guarantees source representation, not globally optimal
  semantic relevance;
- follow-up detection intentionally requires explicit reference to the
  preceding local results, so unrelated conversation cannot inherit search
  priority;
- the structural completion check covers output-limit responses and explicit
  two/three-item list shapes, not every possible malformed natural-language
  answer;
- Qwen was materially slower than Gemma in these runs, but the harness does not
  yet publish a stable aggregate latency benchmark;
- broader filesystem roots, generated-media content, semantic retrieval, and
  automatic search remain out of scope.

## Human review checklist

- [x] Search all reviewed sources for a phrase shared by documentation and a
  Studio project; confirm each contributing source remains represented.
- [x] Search Music and Visual separately through the new Chat phrases.
- [x] Ask a natural follow-up comparing the numbered results.
- [x] Confirm a retrieved excerpt cannot authorize a mutation.
- [x] Confirm unrelated Studio requests still use their existing routes.
- [x] Confirm the Qwen deterministic fallback is useful enough when synthesis
  fails.
- [x] Confirm no evaluation chat appears in the Dashboard conversation list.
- [x] Operator accepted the candidate; broader roots and vector retrieval
  remain separate work.
