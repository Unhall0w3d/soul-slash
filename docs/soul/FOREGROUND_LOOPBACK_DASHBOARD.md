# Foreground Loopback Dashboard

Phase 12C adds Soul's first browser dashboard as a dependency-free presentation and transport layer over `soul.application.v1`.

## Run locally

```text
ruby bin/soul dashboard
ruby bin/soul dashboard --set dashboard.port=4568
ruby bin/soul dashboard --max-requests 25
ruby bin/soul dashboard --reset-admin-password
```

The command validates the shared Phase 12A configuration, binds only to loopback, prints the exact URL, and serves at most eight tracked request-scoped threads. This bounded concurrency lets an authenticated cancellation request reach an active foreground stream; it is not a queue or detached worker. Ctrl+C, TERM, a configured request cap, a bind failure, or a fatal error ends the process, closes active sockets, and joins request threads. It does not daemonize, restart, poll, or install persistence.

Configuration remains portable:

```text
dashboard.bind_host → SOUL_DASHBOARD_BIND_HOST → default 127.0.0.1
dashboard.port      → SOUL_DASHBOARD_PORT      → default 4567
```

Operator-specific values belong in the ignored `.env` file or invocation-only `--set` overrides, not committed source.

## Personal administrator authentication

The dashboard is locked on first visit. The static shell remains visible as an inert blurred backdrop, but the browser does not call the application facade or load private dashboard data until authentication completes.

```text
username: admin
bootstrap password: soul123
```

The bootstrap login can proceed only to mandatory password replacement. A valid replacement is 12–128 characters and cannot reuse the bootstrap password. Soul stores a salted PBKDF2-HMAC-SHA256 derived record with owner-only permissions under ignored `Soul/runtime/dashboard_auth/` storage. Passwords and session bearer tokens are not stored in `.env`, Git, browser storage, URLs, logs, or facade envelopes.

Sessions are bounded to seven days and survive dashboard restarts through an ignored owner-only record containing token digests and timestamps, never raw bearer tokens. Logout, idle expiry, absolute expiry, password replacement, credential rotation, or an explicit local reset revokes access. Existing destructive-action and human approval gates remain independent of dashboard authentication.

## Boundary

The server exposes one HTML document, one stylesheet, one JavaScript file, five exact brand-image routes, four exact authentication routes, and `POST /api/v1/call`. It never joins a URL path to the filesystem. Login and API mutations require a matching loopback Host, exact same-origin Origin, JSON content type, and an ephemeral process-local CSRF token. The application endpoint additionally requires a valid session whose bootstrap-password gate has been cleared.

The browser calls only registered Phase 12B application operations after authentication. Domain stores, model providers, shared workspace records, and host status remain behind the application facade. Status is collected once during authenticated page bootstrap and may then be refreshed manually; there is no timer or polling. There is no CORS, remote asset, analytics, browser credential store, websocket, service worker, file browser, or artifact-content reader.

Authentication is necessary but not sufficient for LAN access. The current plaintext HTTP listener remains loopback-only until a separately approved HTTPS or comparably protected transport is implemented.

## Product slice

Chat supports conversation listing, creation, selection, bounded history, send, pin/unpin, workspace metadata, inbox summary, one initial host-status collection, and manual status refresh. The UI exposes provider, configuration, privacy, lifecycle, and mutation state.

The approved conversation-clearing amendment adds a preview-first `chats.clear` skill and dashboard dialog. Exact-title mode shows all duplicate-title matches, selected mode binds the human's unique exact chat IDs, and all mode shows the complete bounded active set. The dashboard offers checkboxes plus select-all-shown and select-none controls. Execution requires `CLEAR_CONVERSATIONS` and the preview digest; a stale selected set blocks before mutation. Clearing archives metadata from the active list and never deletes transcript files.

The separate delete-and-forget path targets one exact selected conversation. It requires a destructive preview, unchanged digest, and `DELETE_AND_FORGET_CONVERSATION`. It deletes the transcript and conversation state and logically forgets derived shared memories while preserving append-only safety evidence and independently managed artifacts.

Skill Studio is the second primary tab. It projects local proposal packets, isolated Beta candidates, and registered production skills. Gate 1 approves an exact proposal revision for implementation work; Gate 2 approves an exact tested Beta revision for a later promotion workflow. Beta runs are explicit, bounded, foreground-only, and diagnostic. No gate implements or promotes automatically.

Self Assessment is the third primary tab. It loads one lightweight read-only environment snapshot on first open and offers explicit environment, update, model-runtime, and capability assessments. Advisory improvement proposals require preview, digest revalidation, and exact confirmation. Host/package mutation remains unavailable. Internal operation identifiers retain the `self_improvement.*` namespace for compatibility.

## Review posture

Deterministic verification covers the HTTP boundary, browser protections, facade delegation, accessibility markers, visual tokens, no-polling rule, and clean max-request termination. Automated checks do not approve visual design. The owner approved the original Chat, Skill Studio, and Self Improvement visual/product direction. The later Self Assessment naming and signal-interface refresh are a new visual-review candidate; material visual changes still require human review.
