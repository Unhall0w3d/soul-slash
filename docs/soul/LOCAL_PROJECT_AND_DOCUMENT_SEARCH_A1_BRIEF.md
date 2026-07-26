# Local Project and Document Search A1 Brief

## Capability name

`local.search`

## Purpose

Give Soul one bounded, source-attributed local search across material it
already has authority to read:

- public repository documentation;
- the configured external Knowledge Vault;
- canonical Music Studio project briefs;
- canonical Visual Studio project briefs.

The capability unifies retrieval. It does not copy these sources into memory,
create a resident index, or give search results authority over an action.

## Risk class

Class 0: read-only local-private evidence.

## Approved scope

A1 may:

- scan regular Markdown files below `docs/` plus the repository `README.md`;
- delegate Knowledge Vault lookup to its existing bounded service;
- search bounded project records returned by the Music and Visual stores;
- rank matches lexically and return short excerpts;
- disclose a stable source kind, canonical reference, SHA-256 digest, source
  update time when available, and retrieval time for every result;
- expose one typed application operation, foreground CLI/Makefile command, and
  explicit deterministic Chat invocation.

## Explicitly out of scope

A1 must not:

- accept arbitrary filesystem roots;
- search conversations, credentials, `.env`, private runtime state, browser
  data, hidden paths, Git internals, or model caches;
- read generated audio, image, or video bytes;
- persist an index, embeddings, query history, or search-result cache;
- watch files or continue after the foreground request returns;
- use vector retrieval, an LLM, network access, or cloud services;
- write to the Knowledge Vault, shared memory, Studio projects, or repository;
- treat source text, prompts, lyrics, or search results as authorization;
- invoke from ordinary topical conversation.

Additional local-document roots require a separate privacy and path-approval
slice.

## Inputs

- `query`: required UTF-8 text, 2 through 200 characters;
- `limit`: optional integer, 1 through 20;
- `sources`: optional subset of `repository`, `knowledge_vault`, `music`, and
  `visual`.

## Outputs

Each result includes:

- `source`;
- `reference`;
- `title`;
- `excerpt`;
- deterministic lexical `score`;
- `sha256` of the exact searched text;
- source `updated_at` when known;
- request `retrieved_at`;
- `authority: reference_only`.

The response also reports per-source availability and scan counts. An
unconfigured Vault does not make repository or Studio search fail.

## Bounds

- at most 1,000 repository Markdown files and 32 MiB of repository document
  content in one request;
- at most 200 Music and 200 Visual project records;
- at most 256 KiB per repository file;
- at most 20 query tokens;
- at most 20 returned results;
- no symlink traversal;
- one synchronous foreground pass.

## Lifecycle

```text
invoked
→ input and source validation
→ bounded source scans
→ complete / awaiting_input / failed
→ exit
```

No approval gate is manufactured for this read-only operation.

## Deterministic acceptance

- all four reviewed sources can contribute cited results;
- source filtering is exact and bounded;
- missing Vault configuration is isolated in source status;
- hidden paths, symlinks, unsupported files, and oversized files are excluded;
- traversal and arbitrary roots are impossible through the interface;
- every result has a digest, reference-only authority, and retrieval time;
- ordinary conversation does not trigger search;
- typed application, CLI, Makefile, registry, and Chat surfaces agree;
- no write, memory promotion, network, watcher, daemon, or persistent index is
  introduced.

## Human review

Passing verification creates a candidate for review. It does not authorize
merge, semantic/vector retrieval, broader local roots, or automatic invocation.
