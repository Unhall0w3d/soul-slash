# Phase 12C Approved Brief: Foreground Loopback Dashboard and Visual Review

```text
brief_status: approved
implementation_authorized: yes
human_visual_review_required: yes
human_merge_review_required: yes
```

The human owner explicitly pre-approved Phase 12C implementation on 2026-07-14. This brief records the narrow foreground-listener exception and implements the previously approved dashboard product and visual direction.

## Purpose

Deliver the first locally runnable Soul dashboard over the Phase 12B in-process application facade. The slice provides the initial Chat workspace, manual system status, shared artifact rail, and visible two-tab product hierarchy for human visual review.

The dashboard is a transport and presentation layer. It must not implement another conversation runtime, storage format, configuration system, artifact registry, approval authority, memory system, skill runner, or safety policy.

## Risk class

```text
Class 5: Security-sensitive foreground network listener exception
```

The approved exception is one explicitly user-started foreground HTTP listener bound to loopback only. It is not a service, daemon, auto-start process, LAN server, or unattended monitor. It runs only while the foreground dashboard command remains active and stops on Ctrl+C, termination, configured request cap, or fatal bind error.

Music Studio A3 later authorizes up to eight tracked request-scoped threads inside this same listener so an explicit cancellation request can reach a foreground generation stream. Excess requests fail with `429`; shutdown closes sockets and joins all request threads. This does not authorize a queue, detached work, or continuation after the request.

## Approved scope

Phase 12C may:

- add a dependency-free foreground HTTP server using Ruby standard-library sockets;
- bind only to a Phase 12A validated loopback host and port;
- serve one static dashboard document, one stylesheet, one JavaScript module, and an allowlist of existing Soul brand images;
- expose one same-origin JSON endpoint that translates requests into Phase 12B application envelopes;
- add `ruby bin/soul dashboard` as an explicit foreground command;
- support invocation-only non-secret `--set dashboard.bind_host=...` and `--set dashboard.port=...` overrides;
- support a positive `--max-requests` process bound for tests and controlled review sessions;
- render the first two primary tabs in order: Chat, then Skill Studio;
- make Chat functional for list, create, resume, history, send, pin/unpin, workspace refresh, inbox display, and manual system-status refresh;
- show provider, configuration, privacy, lifecycle, mutation, failure, and connectivity state explicitly;
- render Skill Studio as a clearly labeled Phase 12D preview with no generation, implementation, or approval mutation;
- use the approved brand assets, palette, typography fallbacks, and restrained arcane-technical motifs;
- add deterministic HTTP, security, application-delegation, DOM, CSS, accessibility, and no-polling tests;
- start the dashboard locally for the required human visual review;
- keep the review server active only for the explicit foreground review session authorized by the human owner.

## Explicit foreground listener exception

The following normally prohibited behavior is explicitly approved for Phase 12C and nothing broader:

```text
one foreground TCP listener
bind target: validated loopback only
one process
single-connection-at-a-time request handling
user-started only
no daemonization
no fork or worker pool
no background thread
no automatic restart
no service installation
no boot persistence
no LAN or wildcard bind
no background polling
termination: Ctrl+C / TERM / max requests / fatal error
```

The server accept loop exists only while the foreground dashboard command is active. Per-request read timeouts and byte limits remain mandatory.

## Explicitly out of scope

Phase 12C must not:

- bind to `0.0.0.0`, `::`, a LAN address, hostname resolving beyond loopback, or a Unix socket;
- add systemd, launchd, Windows services, cron, scheduled tasks, container definitions, Proxmox deployment, reverse proxy, TLS termination, or automatic startup;
- add Rack, Rails, Sinatra, Node, npm, a frontend framework, package manager dependency, CDN, remote font, analytics, telemetry, tracking, websocket, SSE, or token streaming;
- add authentication, multi-user accounts, remote sessions, browser persistence of credentials, or password management;
- expose arbitrary local files, directory listings, source files, `.env`, logs, chat JSONL paths, memory stores, or unapproved assets;
- send credentials, hidden reasoning, approval tokens, environment data, or unrestricted errors to the browser;
- let route handlers read or mutate domain stores directly instead of the Phase 12B facade;
- add configuration writes, approval mutation, skill execution, skill creation, Codex invocation, artifact content reads, file upload, drag-and-drop files, deletion, archival, export, or voice;
- implement Phase 12D Skill Studio behavior or Phase 12E unified approvals/activity behavior;
- add automatic system-status refresh, timers, polling, watchers, background fetch loops, service workers, or browser push;
- treat automated tests as visual approval.

## Command and lifecycle

```text
ruby bin/soul dashboard
ruby bin/soul dashboard --set dashboard.port=4568
ruby bin/soul dashboard --max-requests 25
```

Startup flow:

```text
invoked
→ resolve and validate Phase 12A configuration
→ prove bind host is loopback
→ open one foreground listener
→ print exact local URL and shutdown instruction
→ serve bounded requests sequentially
→ stop on Ctrl+C / TERM / max requests / fatal error
→ close listener
→ complete / failed / canceled / blocked_for_human_review
→ exit
```

Bind failure must exit cleanly without retry. The server must not select a different port silently.

## HTTP boundary

Allowed routes:

```text
GET  /
HEAD /
GET  /assets/dashboard.css
GET  /assets/dashboard.js
GET  /brand/primary-mark.png
GET  /brand/repo-header.png
GET  /brand/supporting-scene.png
POST /api/v1/call
```

All other paths return 404. Unsupported methods return 405. Static routing uses exact allowlisted paths and never joins an untrusted URL path to the filesystem.

Request bounds:

```text
request line: 2 KiB
headers: 16 KiB total
header count: 64
body: 128 KiB
read timeout: 5 seconds
one request per connection
Connection: close
```

Malformed requests return bounded 400 responses. Oversized requests return 413. Timeouts return 408 where possible. Raw requests, chat bodies, credentials, and headers are not logged.

## Same-origin and browser protections

- Validate `Host` against the configured loopback host/port or an equivalent localhost spelling.
- Require `Content-Type: application/json` for the API.
- Require exact same-origin `Origin` on API POSTs.
- Generate an ephemeral CSRF token at server startup, embed it in the dashboard document, and require it in `X-Soul-CSRF` for API POSTs.
- The token is process-local, never stored, and grants no domain approval authority.
- Send a strict self-only Content Security Policy with no inline scripts or remote resources.
- Send `X-Content-Type-Options: nosniff`, `X-Frame-Options: DENY`, `Referrer-Policy: no-referrer`, and a restrictive Permissions Policy.
- Do not enable CORS.
- Do not cache API responses or the CSRF-bearing HTML document.

## Dashboard composition

### Global shell

- compact Soul mark and wordmark;
- primary tabs: Chat and Skill Studio;
- local connection/provider/configuration indicators;
- visible foreground/local-only posture;
- keyboard-visible focus and reduced-motion behavior.

### Chat tab

Desktop composition:

```text
conversation rail
→ active conversation and composer
→ workspace / status rail
```

Required behavior:

- list and select existing chats;
- create a new chat explicitly;
- load bounded history;
- send one message through `chats.send` with a browser-generated request ID;
- disable the composer during the foreground request;
- show pending, complete, failed, awaiting-input, canceled, and blocked-for-review state in text and color;
- refresh workspace/inbox on chat selection and after a completed send;
- refresh system status only on explicit button activation;
- show empty states without generating sample data;
- render all domain content with safe DOM text APIs, never `innerHTML`.

### Workspace and status rail

- manual system status card with hostname, collection time, scope, and unknown-state disclosure;
- current-chat workspace list with artifact ID, title, kind, privacy, lifecycle, revision/delivery state, and metadata-only label;
- bounded inbox state summary;
- no arbitrary filesystem navigation or artifact-content rendering.

### Skill Studio tab

The tab must be visible and selectable so the product hierarchy can be reviewed. It shows the approved workflow stages and clearly states that implementation begins in Phase 12D. It must not draft, approve, execute, register, or merge anything.

## Visual direction

Use these established tokens:

```text
Arcanum Violet  #6E3DDF
Spectral Teal    #00E2D6
Pale Silver      #E6ECF1
Ember Gold       #FFB14A
Shadow Ink       #0A0D12
Necro Slate      #151922
```

Use system/distributable fallbacks:

```text
display: Georgia / compatible serif
body: Inter-like system sans stack
code: ui-monospace / compatible monospace
```

Use existing imagery sparingly: primary mark in the shell, repo header as a restrained atmospheric accent, and supporting scene only for an empty/preview state. Detailed imagery must not sit behind messages, forms, tables, logs, or code.

The aesthetic target is a precise local operational instrument with restrained arcane character, not generic SaaS gloss and not a theatrical fantasy interface.

## Accessibility and responsive behavior

- semantic landmarks, headings, buttons, form labels, and ARIA tabs;
- keyboard-operable tab switching, chat selection, composer, refresh, and send;
- visible `:focus-visible` styles;
- no lifecycle information conveyed through color alone;
- WCAG-oriented text contrast;
- `prefers-reduced-motion` disables nonessential transitions;
- usable zoom and responsive collapse below desktop width;
- composer remains labeled and error/status text uses an appropriate live region.

## Deterministic tests required

- listener rejects non-loopback configuration before bind;
- command never daemonizes, forks, spawns workers, or installs persistence;
- exact route allowlist serves only approved files and API;
- traversal, encoded traversal, query-path confusion, unknown assets, and unsupported methods fail closed;
- Host validation rejects non-loopback or mismatched authority;
- API rejects missing/wrong Origin, missing/wrong CSRF, wrong content type, malformed JSON, oversized body, and unknown application operation;
- security headers and no-store behavior are present;
- API passes valid envelopes to the Phase 12B facade exactly once and returns its lifecycle unchanged;
- static source contains no polling timer, websocket, SSE, service worker, remote resource, `innerHTML`, `eval`, or dynamic script injection;
- bootstrap does not refresh status;
- status refresh occurs only after an explicit action;
- Chat create/list/history/send and workspace refresh use registered application operations;
- Skill Studio is visibly present but behaviorally inert;
- DOM includes required landmarks, tab roles, labels, live region, and human visual-review marker;
- CSS includes approved tokens, focus-visible, reduced-motion, and responsive rules;
- brand assets are allowlisted and no arbitrary file serving exists;
- foreground max-request bound terminates cleanly in tests;
- Phase 12B and earlier regressions pass.

## Local LLM eval

No additional local LLM eval is required beyond Phase 12B. The dashboard sends Chat through the same tested facade and conversation runtime. Dashboard validation focuses on transport, security, state rendering, and human visual review.

## Human visual review gate

After deterministic tests pass, Codex starts the dashboard locally and opens it for the human owner. Work pauses before Phase 12D behavior.

Review covers:

```text
overall visual tone
information density
two-tab hierarchy
Chat composition
conversation rail
workspace placement
system-status presentation
typography and palette
imagery and motifs
motion and interaction feel
desired additions/removals
```

Automated tests cannot pass this gate. Human feedback may require visual iteration before merge approval.

## Done criteria

- Phase 12B application facade is the only domain boundary used by the dashboard.
- Foreground server binds validated loopback only and shuts down cleanly.
- Request, origin, CSRF, route, asset, and security-header tests pass.
- Functional Chat and manual status behavior pass deterministic tests.
- No polling, background process, daemon, service, LAN binding, or remote dependency is added.
- The first dashboard is opened locally for human visual review.
- Human visual feedback is recorded and required revisions are completed.
- Documentation and review artifact are candidate-complete.
- A separate human merge decision remains required.

## Human brief approval

```text
Outcome: pre-approved
Reviewer: human owner
Date: 2026-07-14
Approved changes: Phase 12C implementation, including the narrowly bounded foreground loopback listener described above
Required changes: pause for human visual review before Phase 12D behavior
Implementation authorized: yes
```
