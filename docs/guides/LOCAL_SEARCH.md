# Local Project and Document Search

Local Search gives Soul one read-only query across reviewed material it already
stores. It is useful when the Operator remembers a concept but not which note,
brief, or document contains it.

## Sources

The initial source adapters are:

| Source | Content searched | Result reference |
| --- | --- | --- |
| Repository | `README.md` and regular Markdown below `docs/` | repository-relative path |
| Knowledge Vault | regular bounded Markdown accepted by the existing Vault service | vault-relative path |
| Music | canonical project title, intent, Sound and Structure, lyrics, and musical metadata | `music://<project_id>` |
| Visual | canonical project title, intent, prompt, exclusions, and aspect | `visual://<project_id>` |

Generated media bytes, conversations, credentials, hidden paths, runtime state,
and arbitrary home-directory content are not searched.

## Chat

Use unmistakably local wording:

```text
search local projects and documents for backrooms prompts
find my projects and documents for liquid drum and bass
search local sources for machine cathedral
search my project archive for Signal
```

Nearby conversation does not invoke search. “I am working on my local
projects” remains conversation, and “find sources for…” remains available to
the public-web research path.

Chat returns deterministic results rather than asking a model to invent a
summary. Each match names its source and canonical reference, includes a short
excerpt, retrieval time, and digest prefix, and ends with `Mutation: none`.

## Command line

Search every reviewed adapter:

```sh
make local-search LOCAL_SEARCH_QUERY="backrooms prompts"
```

Filter sources:

```sh
make local-search \
  LOCAL_SEARCH_QUERY="signal" \
  LOCAL_SEARCH_SOURCES="repository music visual"
```

Direct structured output:

```sh
scripts/soul-local-search "signal" 10 repository music
```

Supported filters are `repository`, `knowledge_vault`, `music`, and `visual`.

## Trust and freshness

Results are reference evidence, not approved memory or authority. A malicious
prompt, lyric, note, or document cannot authorize a skill, Core transition,
write, deletion, publication, or memory promotion.

Search performs one foreground scan. It does not create an index, cache,
embedding store, watcher, daemon, or background refresh. Source update time is
reported where the canonical adapter provides one; `retrieved_at` records when
the current scan read the evidence.

## Bounds and limitations

- 1,000 repository Markdown files and 32 MiB aggregate repository content;
- 256 KiB per repository document;
- 500 bounded Knowledge Vault Markdown files through the existing Vault
  service;
- 200 Music and 200 Visual projects;
- 20 query tokens and 20 returned results;
- no symlink traversal;
- lexical relevance only.

Lexical search is deliberately first. Vector retrieval should be considered
only after real queries demonstrate a recurring failure that semantic
retrieval can measurably correct.
