# Human review — web.research

Candidate: Fundamental Skill Cohort A1, slice 5

Status: accepted; human review complete

## Implemented

- A modern package over the existing `WebResearchService` and foreground CLI.
- Existing configured SearXNG and optional Brave search adapters.
- Existing public-source HTTPS, DNS, redirect, media-type, byte, query, source,
  and overall-time boundaries.
- Existing Chat and Voice routing through `chats.send`.
- Existing provenance-bound conversation evidence, cited synthesis, artifact
  preview handoff, and separately gated reflection/memory flow.
- Registry, invocation, public documentation, generated catalogs, and project
  tracker synchronization.

No new HTTP client, provider adapter, arbitrary URL operation, evidence store,
artifact writer, reflection store, application operation, retry loop, service,
or background process was added.

## Files changed

- `Soul/skills/web/research-web/`
- the existing `web.research` registry metadata
- invocation, public documentation, generated catalogs, and tracker records
- `docs/skills/WEB_RESEARCH.md`
- `docs/soul/FUNDAMENTAL_WEB_RESEARCH_A1_BRIEF.md`
- `docs/assessments/FUNDAMENTAL_WEB_RESEARCH_A1_REVIEW.md`
- `scripts/verify-fundamental-web-research-a1.rb` and Make target

The production service, legacy foreground CLI, conversation runtime, and
evidence implementation were not changed.

## Commands and deterministic results

See `docs/assessments/FUNDAMENTAL_WEB_RESEARCH_A1_REVIEW.md` for the full
validation inventory. The focused verifier runs the original responsive Chat,
lookup, and web-research fixture suite.

## Local LLM eval

Not used for this packaging slice. Routing, network boundaries, evidence
retention, artifact handoff, and lifecycle behavior are deterministic. Model
output cannot approve network safety, source truth, memory, or actions.

## Memory keys

No memory key or skill-private memory was added. Successful evidence remains
conversation-scoped in the shared evidence store. Reflection and promotion
retain their separate explicit human-review paths.

## Lifecycle states

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

The service is bounded foreground work and never remains resident.

## Risk classification

`read_only_network`. No approval is needed to search configured public sources.
Search and source text have no authorization effect. Artifact creation and
memory promotion retain separate existing gates.

## Persistence and safety

```text
Persistent service added: no
Daemon or watcher added: no
Scheduled task added: no
Background continuation added: no
Automatic retry added: no
Arbitrary URL fetch added: no
Private/authenticated source access added: no
Second HTTP or evidence implementation added: no
Skill-private durable memory added: no
```

## Known weaknesses

- Research needs an explicitly configured SearXNG or Brave provider.
- HTML extraction is deliberately simple; PDFs and JavaScript-rendered pages
  are unsupported.
- Some sites deny automated requests or return non-allowlisted media types.
- Source retrieval proves provenance, not source correctness; comparison and
  human judgment remain necessary.
- Local-model synthesis can still omit nuance or misinterpret evidence.
- The exact conversational router is deliberately conservative.

## Human review checklist

- [x] Confirm the package maps only to `WebResearchService` and the existing CLI.
- [x] Confirm provider and public-source address exceptions are distinct.
- [x] Confirm every result and redirect remains public HTTPS and revalidated.
- [x] Confirm query, source, byte, media-type, redirect, and time caps.
- [x] Confirm only query text reaches the search provider.
- [x] Confirm source evidence is untrusted and non-authorizing.
- [x] Confirm artifact and memory paths retain their separate gates.
- [x] Confirm ordinary discussion does not invoke research.
- [x] Confirm no service, watcher, schedule, retry, or background path was added.
- [x] Accept this candidate independently of deterministic test results.

## Human review outcome

```text
Outcome: approved
Reviewer: human owner
Date: 2026-08-02
Decision summary: Accepted web.research and completed Fundamental Skill Cohort A1.
Required changes: none
```
