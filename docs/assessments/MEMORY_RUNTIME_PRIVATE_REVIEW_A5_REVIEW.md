# Memory Runtime and Private Review A5 Review

Status: candidate-complete; awaiting human review

## Outcome

Added one bounded foreground service for two evidence-only questions:

- whether the configured local Ollama embedding profile is reachable, installed,
  and resident according to `/api/tags` and `/api/ps`; and
- whether retrieval produces useful results for the fixed owner-private review
  case file.

The existing read-only Memory Observatory summary also gains a Soul-styled
constellation/lifecycle projection. It is capped at 240 nodes and 400 explicit
duplicate or supersession links and withholds memory content.

The service never starts or stops a runtime, loads or evicts a model, changes
Core selection, rebuilds an index, writes review results, or exposes private
query or memory text.

## Changed files

- `lib/soul_core/memory_runtime_private_review_service.rb`
- `scripts/verify-memory-runtime-private-review-a5.rb`
- `scripts/verify-memory-runtime-private-review-a5-integration.rb`
- `lib/soul_core/application_contract.rb`
- `lib/soul_core/application_facade.rb`
- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `lib/soul_core/memory_observatory_service.rb`
- `scripts/verify-memory-observatory-facade-a2.rb`
- `scripts/verify-memory-observatory-dashboard-a2.rb`
- `docs/soul/MEMORY_RUNTIME_PRIVATE_REVIEW_A5_BRIEF.md`
- `docs/guides/MEMORY_RETRIEVAL_OBSERVATORY.md`
- `docs/ROADMAP.md`
- `Makefile`
- `docs/assessments/MEMORY_RUNTIME_PRIVATE_REVIEW_A5_REVIEW.md`

## Runtime evidence contract

`MemoryRuntimePrivateReviewService#runtime` accepts only a loopback HTTP(S)
embedding endpoint and issues exactly two bounded GET requests: `/api/tags`
and `/api/ps`. It reports the configured profile, protocol, dimensions,
selected Core identity, reachability, exact model installation/residency, and
an explicit compatibility disposition. `free` is always
`incompatible_free_core`; every other Core remains
`qualification_required` until a separate coexistence review approves the
runtime policy. Remote endpoints, malformed configuration, invalid JSON, and
oversized responses fail safely.

## Private review contract

`#private_review` reads the fixed regular non-symlink case file
`Soul/private/memory/retrieval_review_cases.json` and validates:

- schema `soul.memory_retrieval.private_review.v1`;
- an exact closed document and case-key set;
- one to 32 cases;
- bounded opaque case and memory IDs;
- queries no longer than 500 characters;
- one to eight expected IDs and optional forbidden IDs; and
- result limits from one to eight.

It injects the existing retrieval and canonical-memory collaborators, returning
only case IDs, query SHA-256 digests, memory IDs, retrieval metrics, aggregate
recall/reciprocal-rank/forbidden-hit/abstention counts, case/source digests,
retrieval profile, index availability, and a terminal lifecycle state.

## Commands and results

```text
ruby -c lib/soul_core/memory_runtime_private_review_service.rb
# Syntax OK

ruby -c scripts/verify-memory-runtime-private-review-a5.rb
# Syntax OK

ruby scripts/verify-memory-runtime-private-review-a5.rb
# Memory runtime and private review A5 deterministic verification passed.

ruby scripts/verify-memory-runtime-private-review-a5-integration.rb
# Memory runtime/private-review A5 integration verification passed (7 checks).
```

The verifier uses a temporary fixture root, an injected HTTP callback, a
synthetic canonical memory store, and a synthetic retrieval collaborator. It
does not contact Ollama, read the owner-private case file, or persist results.
It also checks that the implementation contains no process execution, POST
requests, Core mutation, or model lifecycle calls. The integration verifier
checks the application contract, facade, Dashboard controls, parameter
rejection, and no-mutation envelope.

## Lifecycle, memory, and risk

- Lifecycle states returned: `complete` or `failed`.
- Memory keys added or promoted: none.
- Canonical memory mutation: none.
- Risk: Class 1 owner-private read and local runtime observation.
- No persistent service, watcher, scheduler, background continuation, or
  network listener was added.

## Known weaknesses and remaining gate

- Runtime residency evidence is limited to what the reviewed Ollama inspection
  endpoints expose; it does not prove accelerator placement.
- A successful exact-model observation intentionally does not approve Core
  coexistence or residency. That requires a separate live, human-reviewed
  qualification.
- The fixed case file must be supplied by the owner; the service does not
  accept arbitrary Dashboard paths or case JSON.

## Human review checklist

- [ ] Confirm only `/api/tags` and `/api/ps` are acceptable runtime reads.
- [ ] Confirm Free Core remains incompatible and all other Core dispositions
      remain qualification-gated.
- [ ] Confirm private review output contains IDs and digests, never query or
      memory content.
- [ ] Confirm the fixed case file and canonical store remain read-only.
- [ ] Decide whether to proceed to a separately approved live coexistence gate.
