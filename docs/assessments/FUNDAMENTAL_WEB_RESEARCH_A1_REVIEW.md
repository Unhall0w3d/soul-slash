# Fundamental Skill Cohort A1 — Web Research Review

Date: 2026-08-02

Branch: `codex/fundamental-web-research-a1`

Status: candidate-complete; human review required

## Implementation

This slice gives Soul's existing bounded research workflow a modern skill
package without adding another implementation path. `WebResearchService`
remains the sole search and source-retrieval service;
`Soul/skills/web/research.rb` remains the direct CLI; explicit Chat and Voice
requests remain on the established `chats.send` conversation route.

The configured provider receives only validated query text. SearXNG may be an
HTTPS provider, loopback HTTP endpoint, or one explicitly opted-in private
authority. Provider redirects cannot change authority. Selected search results
and all redirects are independently constrained to public HTTPS and rechecked
against blocked address ranges.

Successful sources become bounded provenance records in the shared
conversation evidence store. The selected conversation model may synthesize
with source IDs. A request for a supported deliverable passes evidence into the
existing non-mutating artifact preview; research cannot approve the resulting
write. Reflection and approved memory remain separate explicit review paths.

## Authority and privacy

The skill is `read_only_network` and needs no confirmation for public reads.
Search receives neither chat history, private memory, local files, credentials
outside provider authentication, nor artifacts. Sources are untrusted evidence
with `authorization_effect: none`.

No arbitrary URL-fetch operation, private or authenticated source access,
browser automation, scraping fallback, resident process, service, watcher,
schedule, automatic retry, polling, or background continuation is added.

## Deterministic evidence

The focused verifier checks the modern package and retained CLI/service mapping,
the absence of another Ruby transport implementation, registry and invocation
authority, lack of a second application operation, exact routing and ordinary
conversation restraint, unconfigured-provider failure, reviewed limits, SSRF
guard strings, and non-authorizing evidence markers.

It also runs the original responsive Chat and web-research suite. That suite
uses injected DNS and HTTP fixtures to cover Instant Answer hits and misses,
private SearXNG opt-in, rejection of public HTTP providers, provider-authority
redirect pinning, public source retrieval, private result and redirect
rejection, byte and query bounds, artifact grounding, reflection isolation,
unconfigured-provider honesty, stream controls, and foreground completion.

## Results

```text
make verify-fundamental-web-research
11 checks passed

quick_validate.py Soul/skills/web/research-web
Skill is valid

make verify-web-knowledge
passed
```

The final candidate also runs the complete prior Fundamental Skill Cohort A1,
invocation, operator capability, Chat boundary, application API, project
tracker, Skill Studio, generated-documentation, assistant-catalog, and
`make test-soul` regressions before publication.

## Local LLM eval

Not used. This slice changes package metadata and documentation, not model
behavior. LLM output cannot validate SSRF policy, evidence authority, memory,
or action safety.

## Known weaknesses

- provider configuration is required for deep research;
- extraction supports bounded textual HTML/XHTML/plain text, not PDF or
  JavaScript rendering;
- public sites may reject automated requests;
- evidence provenance does not make every source correct;
- synthesis still requires citation and human review; and
- exact conversational routing remains conservative.

## Memory and lifecycle

No memory key, private format, cache, or index was added. Shared
conversation-evidence retention and conversation forgetting remain unchanged.
Reflection and memory promotion retain their separate review gates. Invocations
terminate as `complete`, `failed`, `awaiting_input`, `canceled`, or
`blocked_for_human_review` without resident work.

## Risk classification

`read_only_network`. Provider and source requests are bounded foreground reads.
Source content cannot authorize an action. Artifact writes and durable memory
remain separately human-gated. Human review is still required.

## Human review

Review the sole-service mapping, provider exception, source SSRF controls,
limits, provenance, source distrust, Chat/Voice routing, artifact and memory
separation, and absence of scraping fallback, persistence, retry, or background
work. Passing tests does not authorize merge or cohort acceptance.
