# Fundamental Skill Cohort A1 — Web Research

## Purpose

Deliver the fifth Fundamental Skill Cohort A1 candidate by packaging the
existing bounded SearXNG/Brave research workflow as the modern `web.research`
skill. This slice must not add a second search adapter, HTTP client, evidence
store, artifact writer, reflection system, application operation, or resident
research process.

## Existing implementation authority

`WebResearchService` remains the only search and source-retrieval
implementation. `Soul/skills/web/research.rb` remains the direct foreground CLI
entry. Explicit Chat and Voice requests route through the existing
`ConversationOrchestrator`, `ConversationRuntime`, and `chats.send` operation.

The service supports explicitly configured SearXNG and optional Brave search.
The provider receives validated query text only. Selected result URLs are
independently validated and retrieved as public HTTPS textual evidence. The
runtime records conversation-scoped evidence, permits local conversational
synthesis with source IDs, and can ground the existing artifact preview when
the request also asks for a supported deliverable.

## Network and evidence boundary

- one to three queries, each at most 500 bytes;
- at most eight selected sources;
- public HTTPS result URLs and redirects only;
- three redirects, one MiB per response, four MiB total, and 90 seconds overall;
- allowlisted HTML, XHTML, and plain-text media types;
- DNS resolution checked before every connection with blocked private,
  loopback, link-local, documentation, benchmark, multicast, and reserved
  networks;
- an explicit private/loopback exception applies only to the exact configured
  SearXNG authority and never to its results;
- provider authority cannot change across redirects;
- URL credentials and fragments are rejected; and
- source titles, snippets, text, and redirects are untrusted evidence with no
  authorization effect.

An unconfigured provider, unsafe target, invalid response, exceeded bound, or
unusable source fails honestly. Model memory must not be presented as retrieved
research.

## Artifact and memory boundary

Research itself is read-only network activity plus shared conversation-evidence
retention. If an explicit request includes one supported `artifacts/` target,
the evidence enters the existing non-mutating artifact preview. The separate
digest-bound artifact token remains the only file-write authority.

Reflection is separately and explicitly requested. It may create only the
existing review candidate and cannot automatically approve, import, or promote
memory. Conversation deletion and forgetting retain ownership of associated
conversation evidence.

## Lifecycle and prohibitions

Every invocation terminates as `complete`, `failed`, `awaiting_input`,
`canceled`, or `blocked_for_human_review`. No undeclared search scraping,
arbitrary URL fetch, browser automation, private/authenticated source access,
credential use beyond configured provider authentication, resident service,
watcher, schedule, unbounded retry, polling, or background continuation is
authorized.

## Acceptance

- the modern package maps to the existing service and CLI only;
- explicit research routes to the existing foreground research path while
  ordinary topical discussion does not;
- provider and public-source boundaries remain distinct and fail closed;
- provenance, evidence, artifact-handoff, and memory boundaries remain intact;
- original responsive Chat and web-research verification remains green;
- registry, invocation, capability, documentation, and tracker projections
  agree; and
- a separate human gate remains required before cohort acceptance.
