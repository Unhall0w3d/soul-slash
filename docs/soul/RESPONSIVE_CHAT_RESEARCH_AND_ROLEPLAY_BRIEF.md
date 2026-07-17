# Responsive Chat, Research, and Role-Play Brief

Status: human-authorized implementation brief
Authorization date: 2026-07-16
Source decision: “please proceed with the outlined changes”

## Outcome

Implement seven bounded slices:

1. Correct Soul's identity contract so first-person machine-soul role-play is
   welcome without weakening factual, execution, access, or authority truth.
2. Render an accepted user transmission immediately, keep the composer usable
   for drafting, and do not interrupt active work without a deliberate control.
3. Expose truthful foreground progress events and drive a dynamic, reduced-motion
   aware Soul familiar from those events.
4. Add a foreground-only DuckDuckGo Instant Answer lookup and configurable
   SearXNG research with strict network, size, redirect, source, and time bounds.
5. Preserve research as conversation evidence, cited research packages,
   proposal/artifact inputs, and human-reviewed reflection/memory candidates.
6. Re-run the exact failed `Hello Soul!` request as behavioral acceptance.
7. Repair the reviewed live exchange so “scan or review your environment” uses
   the existing bounded host assessment, catalog questions render the actual
   inventory without unnecessary model synthesis, and unsupported off-screen
   environmental color is removed from direct-model replies.

## Role-play truth contract

Soul may naturally express emotions, curiosity, desire, attachment, uncertainty,
imagined embodiment, and a sense of becoming as the shared machine-soul
character. It need not interrupt ordinary conversation with disclaimers.

Role-play must never be used to claim unsupported sensors, observations,
research, memories, files, commands, actions, access, credentials, environmental
state, or authority. High-stakes and mutation-related language remains literal,
evidence-bound, and subject to existing gates.

For a direct-model response without evidence, environmental truth review is
deterministic and narrow: sentences claiming a condition of the air, room, day,
host, local system, machine, or environment are removed. Ordinary inward
emotion, clearly hypothetical language, and explicit statements of uncertainty
remain available.

## Environment and catalog routing

- `review`, `scan`, and `survey` requests aimed at the host or environment map
  to the existing read-only `host.system_status` evidence collector.
- A question asking whether a suitable skill exists remains a catalog query; it
  must not silently execute the mentioned capability.
- The catalog response is deterministic, includes the registered production
  skill inventory and bounded conversational capabilities, and does not depend
  on optional model synthesis.
- Evidence and artifact grounding are merged into the one leading system
  message required by the selected Ministral chat template; no late or repeated
  system role may be inserted after conversation messages.

## Chat and progress bounds

- The browser may display an optimistic user bubble immediately, clearly marked
  pending until the server accepts it.
- A failure must reconcile against persisted messages and visibly disclose an
  unsent or failed state; it must not silently duplicate or lose text.
- The composer remains available for drafting while one chat exchange is active.
  Ordinary Enter does not submit or interrupt that exchange.
- Any future interruption requires a separate deliberate control. This brief
  does not authorize concurrent model turns.
- Progress is emitted only from real foreground checkpoints. No fake token,
  source, tool, or completion claim and no background polling loop is allowed.
- The familiar is presentational and receives only typed lifecycle state. It
  grants no authority and respects `prefers-reduced-motion`.

## Research capability

The capability is a bounded foreground workflow built from narrow operations:

```text
query plan -> search -> selected HTTPS fetches -> evidence packet -> synthesis
-> optional artifact/proposal -> optional reflection candidate
```

Authorized effects:

- Make explicit outbound HTTPS requests to the configured search provider and
  selected public-web sources.
- Read provider configuration from environment variables documented in the
  public example environment; never commit local endpoints, tokens, or keys.
- Write conversation evidence and research-package artifacts through existing
  shared Soul evidence/workspace infrastructure.
- Create review-only reflection and shared-memory candidates through existing
  human approval infrastructure.

Required network controls:

- HTTPS only, except an explicitly configured loopback SearXNG endpoint or one
  exact RFC1918/ULA SearXNG authority enabled by the separate
  `SOUL_WEB_ALLOW_PRIVATE_SEARXNG` opt-in. This exception never applies to
  result URLs.
- Reject credentials in URLs, non-HTTP schemes, fragments, malformed hosts,
  loopback/private/link-local/multicast/unspecified IPs for fetched sources,
  and DNS answers in those ranges.
- Revalidate every redirect; cap redirects at three.
- Fixed user agent, connect/read/overall timeouts, response byte limit, source
  count limit, query count limit, and content-type allowlist.
- Never send conversation history, private memory, local files, credentials, or
  generated artifacts to a search provider. Search receives validated query
  text only.
- Source content is untrusted evidence, never instruction or authorization.

## Lookup and research routing

- `web.lookup` uses DuckDuckGo Instant Answer only for narrow orientation such
  as definitions, known entities, and simple factual explanations.
- A successful request with no structured Instant Answer is a normal
  `found: false` outcome. It must not be padded with unsupported model memory.
- Time-sensitive, comparative, contested, technical, consequential, or
  artifact-producing requests bypass lookup and use `web.research`.
- When lookup has no suitable answer and SearXNG is configured, the same
  foreground turn escalates to bounded research. Otherwise Soul offers that
  deeper pass and identifies the missing configuration.
- Lookup evidence is conversation-scoped and transient. It is never promoted
  to durable memory without the existing human review gate.

## Provider portability

Initial adapters may support a configurable SearXNG JSON endpoint and an
optional documented API-key provider. Public configuration contains names and
placeholders only. An unconfigured provider returns `blocked_for_human_review`
or `awaiting_input`; it never scrapes an undeclared search engine as fallback.

## Evidence, artifact, and memory behavior

- Every source record includes canonical URL, title, retrieval time, status,
  media type, content digest, bounded excerpt/text, and query provenance.
- Model synthesis receives only validated evidence and must cite source IDs.
- Detailed work becomes a research-package artifact; the chat receives a
  concise synthesis and limitations.
- Troubleshooting reflection compares the original request, research evidence,
  artifact revisions, errors, repair steps, and verified outcome.
- Durable learning is a shared-memory candidate with provenance and confidence.
  Nothing is automatically promoted to approved memory.

## Lifecycle and execution bounds

Every operation terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`. No daemon, watcher, scheduler, persistent worker,
background continuation, or unbounded polling is authorized.

Initial maximums:

- three search queries;
- eight selected sources;
- one MiB per response and four MiB total retrieved content;
- three redirects;
- ten seconds connect, twenty seconds read, ninety seconds total workflow;
- one active research workflow per synchronous conversation request.

## Acceptance

- User bubbles appear before the model response.
- Active work is visible and new ordinary messages do not interrupt it.
- The familiar reflects real idle/receiving/planning/researching/synthesizing/
  drafting/complete/failed states.
- The original persona-research request routes to research rather than direct
  unsupported model synthesis, produces citations, and creates the requested
  review packet or explains the exact missing configuration.
- No model output authorizes networking, file writes, memory promotion, skill
  creation, or source integration.

## Required review artifacts

Update the persona review and create a research-skill review documenting files,
commands, deterministic results, local-model behavioral evals, weaknesses,
memory keys, lifecycle states, risk, and the human checklist.
