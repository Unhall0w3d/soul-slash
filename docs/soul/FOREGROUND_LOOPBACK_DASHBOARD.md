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

The separate delete-and-forget path targets one exact selected conversation. It requires a destructive preview, unchanged digest, and `DELETE_AND_FORGET_CONVERSATION`. It deletes the transcript and conversation state and logically forgets derived shared memories while preserving append-only safety evidence and independently managed artifacts.

Skill Studio is the second primary tab. It projects local proposal packets, isolated Beta candidates, and registered production skills. Gate 1 approves an exact proposal revision for implementation work; Gate 2 approves an exact tested Beta revision for a later promotion workflow. Beta runs are explicit, bounded, foreground-only, and diagnostic. No gate implements or promotes automatically.

Self Improvement is the third primary tab. It loads one lightweight read-only environment snapshot on first open and offers explicit environment, update, model-runtime, and capability assessments. Advisory improvement proposals require preview, digest revalidation, and exact confirmation. Host/package mutation remains unavailable.

## Review posture

Deterministic verification covers the HTTP boundary, browser protections, facade delegation, accessibility markers, visual tokens, no-polling rule, and clean max-request termination. Automated checks do not approve visual design. The owner approved the current Chat, Skill Studio, and Self Improvement visual/product direction; later visual changes still require human review.
