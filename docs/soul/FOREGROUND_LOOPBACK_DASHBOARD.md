# Foreground Loopback Dashboard

Phase 12C adds Soul's first browser dashboard as a dependency-free presentation and transport layer over `soul.application.v1`.

## Run locally

```text
ruby bin/soul dashboard
ruby bin/soul dashboard --set dashboard.port=4568
ruby bin/soul dashboard --max-requests 25
```

The command validates the shared Phase 12A configuration, binds only to loopback, prints the exact URL, and serves requests sequentially in the foreground. Ctrl+C, TERM, a configured request cap, a bind failure, or a fatal error ends the process. It does not daemonize, restart, poll, or install persistence.

Configuration remains portable:

```text
dashboard.bind_host → SOUL_DASHBOARD_BIND_HOST → default 127.0.0.1
dashboard.port      → SOUL_DASHBOARD_PORT      → default 4567
```

Operator-specific values belong in the ignored `.env` file or invocation-only `--set` overrides, not committed source.

## Boundary

The server exposes one HTML document, one stylesheet, one JavaScript file, three exact brand-image routes, and `POST /api/v1/call`. It never joins a URL path to the filesystem. API calls require a matching loopback Host, exact same-origin Origin, JSON content type, and an ephemeral process-local CSRF token.

The browser calls only registered Phase 12B application operations. Domain stores, model providers, shared workspace records, and host status remain behind the application facade. Status is collected once during page bootstrap and may then be refreshed manually; there is no timer or polling. There is no CORS, remote asset, analytics, browser credential store, websocket, service worker, file browser, or artifact-content reader.

## Product slice

Chat supports conversation listing, creation, selection, bounded history, send, pin/unpin, workspace metadata, inbox summary, one initial host-status collection, and manual status refresh. The UI exposes provider, configuration, privacy, lifecycle, and mutation state.

The approved conversation-clearing amendment adds a preview-first `chats.clear` skill and dashboard dialog. Exact-title mode shows all duplicate-title matches; all mode shows the complete bounded active set. Execution requires `CLEAR_CONVERSATIONS` and the preview digest. Clearing archives metadata from the active list and never deletes transcript files.

Skill Studio is present as the second primary tab so the product hierarchy can be reviewed. Its workflow is intentionally inert until a separate Phase 12D implementation decision.

## Review posture

Deterministic verification covers the HTTP boundary, browser protections, facade delegation, accessibility markers, visual tokens, no-polling rule, and clean max-request termination. It does not approve the visual design. Phase 12C remains `blocked_for_human_review` until the owner reviews the running dashboard and records requested revisions or acceptance.
