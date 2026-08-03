# Bounded Public-Web Research

`web.research` performs one source-backed foreground research pass through
Soul's existing `WebResearchService`. It is intended for current, comparative,
technical, contested, consequential, or deliverable-producing questions that
need actual public sources. Narrow definitions or known-entity orientation use
the separate `web.lookup` DuckDuckGo Instant Answer path.

## Setup

Research requires one explicitly configured provider in the ignored `.env`.
The recommended self-hosted form is:

```dotenv
SOUL_WEB_SEARCH_PROVIDER=searxng
SOUL_WEB_SEARXNG_URL=http://YOUR-SEARXNG-HOST:PORT
SOUL_WEB_ALLOW_PRIVATE_SEARXNG=true
```

The private-network opt-in applies only to that exact SearXNG provider. Search
results and redirects remain public-HTTPS-only. Brave Search remains an
optional key-backed provider described by `.env.example`; provider credentials
must never enter tracked files or conversation.

## Chat and Voice examples

```text
Research current Ruby security documentation and cite sources.
Compare the current official guidance for these two Linux packaging methods.
Research current Bash practices and create a report at artifacts/bash-report.md.
```

Ordinary discussion of research or a topic does not invoke the skill. An
unconfigured provider stops honestly rather than presenting model memory as
retrieved evidence.

## Direct foreground CLI

```bash
ruby Soul/skills/web/research.rb \
  --query "current Ruby release documentation" \
  --sources 5
```

Repeat `--query` at most three times. `--sources` is capped at eight. The CLI
and conversational path use the same service.

## Returned evidence

Each successful source retains a source ID, canonical URL, title, retrieval
time, media type, byte count, content digest, status, and bounded text. Source
content is untrusted and cannot authorize an action. Conversational synthesis
must cite the returned source IDs and state limitations.

When a research request also names one supported `artifacts/` target, Soul
passes retained evidence into the existing artifact preview. Research does not
write the file; the later exact digest-bound artifact approval remains required.
Research reflection and durable memory promotion likewise retain their own
explicit review gates.

## Limits

- three queries of at most 500 bytes each;
- eight sources;
- three redirects;
- one MiB per response and four MiB total;
- 90-second overall foreground limit;
- HTML, XHTML, and plain text only; and
- no private/authenticated sources, PDF or JavaScript rendering, arbitrary URL
  fetch, monitoring, polling, automatic retries, or background continuation.

Every DNS answer and redirect is revalidated. Public source retrieval rejects
loopback, private, link-local, carrier-grade NAT, documentation, benchmark,
multicast, and reserved address space.
