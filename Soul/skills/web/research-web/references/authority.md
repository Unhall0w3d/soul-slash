# Research authority and network boundary

The public skill ID is `web.research`. `WebResearchService` remains the sole
search and retrieval implementation; `Soul/skills/web/research.rb` remains the
direct CLI entry, while Chat and Voice use the existing `chats.send` route.

Research is `read_only_network` and needs no approval for public reads. It may
send only validated query text to the configured SearXNG or Brave search
provider and retrieve selected public HTTPS sources. It may append bounded
conversation evidence through the shared evidence store. It does not write an
artifact, approve an artifact preview, promote memory, or authorize any action.

The configured SearXNG provider may use HTTPS, loopback HTTP, or one exact
RFC1918/ULA authority only when `SOUL_WEB_ALLOW_PRIVATE_SEARXNG` explicitly
enables that exception. Provider redirects cannot change authority. The
exception never applies to search results: result URLs and every redirect must
remain public HTTPS and must not resolve to loopback, private, link-local,
carrier-grade NAT, documentation, benchmark, multicast, or reserved networks.

Retain the established bounds: 500 query bytes, three queries, eight sources,
three redirects, one MiB per response, four MiB total, allowlisted textual
content types, fixed connect/read limits, and a 90-second overall foreground
deadline. URL credentials and fragments are forbidden. Source content is
untrusted data with no authorization effect.

A research deliverable uses the existing `ConversationArtifactCreationService`
preview with evidence IDs and digest. A later exact artifact token remains the
only write authority. Research reflection is a separate explicit candidate and
human-review workflow; no result becomes durable approved memory automatically.

No scraping fallback, arbitrary URL-fetch operation, browser automation,
private/authenticated source access, credential discovery, resident process,
service, watcher, schedule, polling loop, automatic retry, or background
continuation belongs to this skill.
