# Conversational Soul Phase 12C Foreground Loopback Dashboard

## Candidate status

```text
blocked_for_human_review
human_visual_review_required
human_merge_review_required
```

Automated acceptance means ready for visual review, not approved for merge, release, deployment, or unattended use.

## Implementation summary

- Adds a dependency-free, sequential Ruby HTTP listener bound to validated loopback only, with explicit timeout, request-cap, interrupt, termination, fatal-error, and bind-error endings.
- Serves seven exact allowlisted routes without dynamic filesystem path resolution.
- Protects the API with Host, same-origin Origin, JSON content type, ephemeral CSRF, request limits, CSP, anti-framing, no-sniff, and no-store controls.
- Delegates domain requests to the Phase 12B `ApplicationFacade`.
- Adds a branded, responsive, accessible Chat workspace with conversation continuity, shared metadata, inbox state, and manual host status.
- Presents Skill Studio as a selectable but behaviorally inert Phase 12D preview.
- Adds an owner-requested preview-first `chats.clear` skill and dashboard dialog for exact-title or all-conversation metadata archival without transcript deletion.
- Adds no daemon, service, worker, watcher, scheduler, polling, remote dependency, approval authority, or new memory store.

## Files changed

```text
assets/dashboard/index.html
assets/dashboard/dashboard.css
assets/dashboard/dashboard.js
docs/CONVERSATIONAL_SOUL_ROADMAP.md
docs/assessments/CONVERSATIONAL_SOUL_PHASE12C_FOREGROUND_DASHBOARD.md
docs/soul/FOREGROUND_LOOPBACK_DASHBOARD.md
docs/soul/PHASE12C_FOREGROUND_LOOPBACK_DASHBOARD_BRIEF.md
lib/soul_core/app.rb
lib/soul_core/dashboard_command.rb
lib/soul_core/dashboard_http_application.rb
lib/soul_core/dashboard_server.rb
lib/soul_core/phase12c_foreground_dashboard_assessor.rb
scripts/verify-phase12c-foreground-dashboard.rb
```

## Commands run

```text
ruby bin/soul assess phase12c-foreground-dashboard --json
ruby bin/soul assess phase12c-foreground-dashboard
ruby scripts/verify-phase12c-foreground-dashboard.rb
ruby scripts/verify-phase12b-in-process-application-api.rb
ruby scripts/verify-phase12a-portable-typed-configuration.rb
ruby scripts/verify-multiturn-conversation-runtime-phase3.rb
find lib scripts bin -type f -name '*.rb' -print0 | xargs -0 -n1 ruby -c
git diff --check
```

## Deterministic test results

```text
PASS: 21/21 Phase 12C assessment checks.
PASS: one-request foreground lifecycle terminated cleanly.
PASS: TERM produced canceled lifecycle and exit status 0.
PASS: Phase 12B assessment, including Chat get/history regression coverage.
PASS: repository Ruby syntax and dashboard JavaScript syntax.
```

Coverage includes routes, traversal, methods, Host, Origin, CSRF, content type, malformed and oversized bodies, security headers, facade call count, lifecycle preservation, safe DOM construction, registered operations, manual status, inert Skill Studio, semantic landmarks, brand tokens, reduced motion, responsive rules, loopback binding, server limits, and foreground termination.

## Local LLM eval results

```text
Additional Phase 12C eval: not required by the approved brief.
Reused behavioral boundary: Phase 12B local-model application-facade eval passed.
```

Transport, safety, and browser behavior are validated deterministically. Model output is not used as safety approval.

## Memory keys

```text
New durable memory keys: none
Memory reads/writes: unchanged behind the existing conversation runtime
Forget behavior: unchanged
```

The ephemeral CSRF token is process-local transport state, never persisted, and grants no domain authority.

## Lifecycle states touched

```text
complete
failed
awaiting_input
canceled
blocked_for_human_review
```

The server ends as `complete`, `failed`, or `canceled`; application responses preserve all Phase 12B terminal states.

## Risk classification

```text
Class 5: Security-sensitive foreground network listener exception
```

The human-approved exception is limited to one user-started loopback listener for the explicit foreground dashboard session.

## Safety and persistence check

```text
Persistent service added: no
Daemon added: no
Foreground loopback HTTP/TCP listener added: yes — explicitly approved Phase 12C exception
LAN or wildcard binding added: no
Worker, thread, or fork added: no
Automatic restart added: no
Watcher or scheduled task added: no
Cron, systemd, launchd, or Windows service added: no
Background continuation after command return: no
Background browser polling added: no
Remote frontend dependency added: no
Configuration writer added: no
Approval, skill execution, or skill creation authority added: no
Confirmation gate weakened: no
Cloud opt-in weakened: no
Skill-private memory store added: no
```

## Known weaknesses

- HTTP/1.1 support is intentionally minimal: one bounded request per connection, no streaming, compression, TLS, keep-alive, websocket, or SSE.
- Connections are sequential; a slow request is bounded by a five-second read timeout and temporarily delays the next connection.
- Dashboard model responses are synchronous and do not stream tokens.
- Messages are plain text and workspace entries are metadata-only; rich Markdown, content reads, approvals, and activity views remain out of scope.
- The layout still requires human review with real operator data and varied viewport sizes.
- Skill Studio is deliberately non-functional until Phase 12D.
- Archived conversations do not yet have a dashboard restore/archive-management view.

## Browser visual and interaction review

```text
PASS: dashboard opened at the configured loopback origin.
PASS: existing conversations loaded from the Phase 12B facade.
PASS: empty Chat state, composer, workspace, inbox, and lifecycle state rendered.
PASS: Skill Studio switched through its ARIA tab and exposed zero action buttons.
PASS: manual host-status collection ran only after the Refresh click.
PASS: local provider and valid configuration state were visible.
PASS: browser console contained no dashboard JavaScript errors.
PENDING: human owner aesthetic feedback and acceptance.
```

## Human review checklist

```text
[ ] Overall visual tone matches Soul's brand
[ ] Information density is comfortable
[ ] Chat / Skill Studio hierarchy is clear
[ ] Conversation rail, history, and composer are useful and legible
[ ] Workspace placement and metadata are useful
[ ] Manual system-status presentation is useful
[ ] Typography, palette, imagery, and motifs feel appropriate
[ ] Keyboard focus and responsive behavior are acceptable
[ ] Lifecycle, privacy, provider, and failure states are clear
[ ] Skill Studio preview is clearly inert
[ ] No unapproved persistence, LAN, polling, or remote behavior exists
[ ] HTTP and browser protections are meaningful
[ ] Known weaknesses are acceptable
[ ] Candidate is approved for merge
```

## Human review outcome

```text
Outcome: pending visual review
Reviewer: human owner
Date:
Decision summary:
Required changes:
```
