# Local Project and Document Search A1 Review

Status: candidate-complete; human review required

## Implementation

Added one bounded lexical search across repository documentation, the external
Knowledge Vault, and canonical Music and Visual project briefs. Every result
preserves its source adapter, canonical reference, exact searched-text digest,
source update time when available, retrieval time, excerpt, and
`reference_only` authority.

The implementation is synchronous and rescans approved sources on each
request. It creates no index, embeddings, query log, cache, watcher, service,
or memory record.

## Files changed

- `Makefile`
- `README.md`
- `Soul/skills/registry.yaml`
- `config/invocation_catalog.yaml`
- `config/project_tracker_seed.json`
- `docs/ARCHITECTURE.md`
- `docs/ASSISTANT_SKILL_CATALOG.md`
- `docs/CURRENT_STATE.md`
- `docs/ROADMAP.md`
- `docs/guides/LOCAL_SEARCH.md`
- `docs/soul/LOCAL_PROJECT_AND_DOCUMENT_SEARCH_A1_BRIEF.md`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `lib/soul_core/chat_responder.rb`
- `lib/soul_core/conversation_orchestrator.rb`
- `lib/soul_core/dashboard_capability_guide.rb`
- `lib/soul_core/local_search_chat_controls.rb`
- `lib/soul_core/local_search_service.rb`
- `scripts/soul-local-search`
- `scripts/verify-local-search-a1.rb`

The ignored owner-local Project Timeline is updated through
`ProjectTrackerService` and is not part of the Git diff.

## Deterministic evidence

`ruby scripts/verify-local-search-a1.rb` covers:

- results from all four reviewed adapters;
- citations, digests, retrieval timestamps, and reference-only authority;
- exact source filtering;
- isolation of unavailable Vault configuration;
- hidden, symlinked, and oversized document exclusion;
- bounded queries, files, bytes, projects, and results;
- explicit Chat routing without ordinary-conversation or web-research theft;
- typed application validation;
- registry risk metadata;
- absence of network and resident behavior.

A live owner-local query for `backrooms` scanned 543 repository documents,
17 Visual projects, and returned the canonical Visual reference
`visual://visual_project_ff1459682284bb0f` for **The Hallway Moves First —
Reconfiguration**.

## Local LLM evaluation

None. A1 uses deterministic lexical retrieval and rendering. Model synthesis
would make the grounding boundary less clear and is not needed to validate
path safety, citations, or routing.

## Memory and lifecycle

- Shared memory read: none.
- Shared memory write: none.
- Knowledge Vault write: none.
- Studio mutation: none.
- Lifecycle: `complete`, `awaiting_input`, or `failed`.
- Risk: read-only local-private evidence.

## Known weaknesses

- lexical matching does not understand synonyms or conceptual similarity;
- Knowledge Vault results do not currently expose filesystem modification
  timestamps, though each result retains its exact content digest and request
  retrieval time;
- A1 searches current project briefs, not candidate audio, pixels, motion
  frames, reviews, or full lineage;
- additional personal-document roots remain out of scope pending an explicit
  privacy and path-approval contract;
- deterministic Chat output retrieves evidence but does not yet synthesize
  multiple matches into a model-authored answer.

## Human review checklist

- [ ] Search for a phrase known to exist in repository documentation.
- [ ] Search for a Knowledge Vault topic.
- [ ] Search for a Music project concept without knowing its exact title.
- [ ] Search for a Visual project concept without knowing its exact title.
- [ ] Confirm ordinary project conversation does not invoke search.
- [ ] Confirm “find sources” remains public-web research rather than local
  search.
- [ ] Confirm returned references and excerpts are useful on the Dashboard.
