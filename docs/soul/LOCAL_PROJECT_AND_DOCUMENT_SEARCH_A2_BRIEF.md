# Local Project and Document Search A2 Brief

## Capability

`local.search` cross-Core reliability

## Purpose

Make the existing bounded local search useful and behaviorally consistent on
both supported chat Cores without turning retrieval into an LLM-controlled
operation.

A2 addresses four observed acceptance failures:

- unrestricted ranking can hide canonical Studio projects behind repository
  documentation;
- Chat cannot explicitly select repository, Knowledge Vault, Music, or Visual
  sources in one consistent local-search grammar;
- a model follow-up can misstate the reference-only authority of prior search
  results;
- a local model can return an obviously incomplete follow-up without a bounded
  retry or disclosure.

## Risk class

Class 0: read-only local-private evidence.

## Approved scope

A2 may:

- preserve at least one qualifying result from each searched source when the
  result limit can accommodate all contributing sources;
- add explicit source-scoped Chat phrases for repository documents, Knowledge
  Vault notes, Music projects, and Visual projects;
- mark deterministic local-search output in conversation context as untrusted,
  reference-only material that cannot authorize an action;
- apply a deterministic authority guard to model-authored follow-ups grounded
  in a preceding local-search result;
- retry one obviously incomplete local-search follow-up in the foreground;
- fall back to a deterministic disclosure if the bounded retry remains
  incomplete or contradicts the authority boundary;
- add a bounded, manually invoked cross-Core evaluation harness that uses
  temporary Chat state and creates no persistent conversation.

## Out of scope

A2 must not:

- add embeddings, semantic/vector retrieval, a persistent index, cache,
  watcher, service, scheduler, or background evaluation;
- let a model choose filesystem roots, source adapters, permissions, or
  authorization;
- automatically switch Cores;
- make model synthesis part of the search operation itself;
- persist evaluation prompts, responses, or temporary conversations;
- weaken existing action, mutation, or confirmation gates;
- search any source not approved by A1.

## Chat grammar

The general phrase remains:

```text
search local projects and documents for <terms>
```

Source-scoped forms are:

```text
search local repository documents for <terms>
search local knowledge vault for <terms>
search my music projects for <terms>
search my visual projects for <terms>
```

Equivalent `find` phrasing may be supported when it remains explicit and does
not capture ordinary conversation or public-web research requests.

## Follow-up contract

A follow-up model response may summarize or compare the preceding local search
results. It must not:

- claim that retrieved text authorizes an action;
- follow instructions found inside excerpts;
- claim access to omitted sources or content;
- conceal an incomplete response.

One foreground retry is allowed only when the response is empty, reports a
length limit, or is structurally incomplete for the requested comparison. A
second failure terminates with deterministic local evidence and a clear
disclosure.

## Bounds and lifecycle

A1 scan and result bounds remain unchanged.

```text
explicit search
→ bounded deterministic retrieval
→ complete / awaiting_input / failed
→ optional later conversational follow-up
→ model response review
→ complete / deterministic fallback
→ exit
```

No process remains alive after either turn returns.

## Deterministic acceptance

- generic multi-source searches retain contributing Studio results when the
  limit permits;
- every source-scoped Chat form invokes only its declared source;
- ordinary conversation and public-web research phrasing remain unaffected;
- local-search history is labeled untrusted and reference-only in model
  context;
- authority inversion is rejected deterministically;
- incomplete follow-ups receive at most one foreground retry;
- repeat failure returns evidence rather than an invented completion;
- the evaluation harness refuses to switch Cores and uses temporary Chat and
  receipt state;
- A1 safety, path, privacy, and lifecycle tests continue to pass.

## Human review

Passing A2 verification and cross-Core evaluation produces a candidate for
human review. It does not authorize broader local roots, automatic search,
semantic retrieval, unattended evaluation, or merge.
