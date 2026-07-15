# Phase 12C.1 Approved Brief: Personal Dashboard Authentication

```text
brief_status: approved by human owner instruction
implementation_authorized: yes
lan_binding_authorized: no
persistent_service_authorized: no
human_visual_review_required: yes
human_merge_review_required: yes
```

The human owner explicitly requested this authentication boundary on 2026-07-15. This brief is a narrow addendum to the Phase 12C foreground loopback dashboard brief. Where the older brief excludes authentication, this approved addendum authorizes only the behavior below. It does not authorize LAN binding, TLS termination, a persistent service, or multiple accounts.

## Purpose

Require a personal administrator login before the browser may load private dashboard data or call the Soul application facade. The unauthenticated page retains the dashboard composition as a blurred, inert visual backdrop with an accessible login surface above it.

## Risk class

```text
Class 5: security-sensitive authentication and private-runtime credential storage
```

## Approved scope

- One fixed administrator username: `admin`.
- A first-run bootstrap password of `soul123`.
- Mandatory password replacement before dashboard data or controls become available.
- No sign-up, account creation, role management, password recovery email, OAuth, or general user registry.
- Password hashing with Ruby/OpenSSL PBKDF2-HMAC-SHA256, a unique random salt, and 600,000 iterations.
- A new password policy of 12 to 128 UTF-8 characters; the bootstrap password cannot be reused.
- One ignored local credential record under `Soul/runtime/dashboard_auth/`, written with owner-only permissions and no plaintext password.
- Bounded in-memory server sessions with random bearer tokens, idle and absolute expiry, and a maximum session count.
- Host-only session cookies with `HttpOnly`, `SameSite=Strict`, and no `Domain` attribute. `Secure` is required when a later approved HTTPS transport is active.
- Exact same-origin and CSRF validation for login, password change, logout, and application calls.
- A bounded failed-login window returning `429` after repeated failures. No timer, sleeper, polling loop, or background cleanup process is permitted; stale state is pruned during foreground requests.
- An explicit local reset command may restore the bootstrap credential and revoke all active sessions. It must exit without starting a listener.
- Logout and session-expiry behavior that re-locks and blurs the dashboard.
- Deterministic authentication, HTTP-boundary, DOM, lifecycle, privacy, and regression tests.

## Required lifecycle

```text
first server start
→ create owner-only bootstrap credential hash
→ unauthenticated / dashboard locked
→ admin + bootstrap password accepted
→ authenticated but password_change_required / dashboard still locked
→ current password + valid replacement submitted
→ credential atomically replaced and other sessions revoked
→ authenticated / dashboard unblurred / application bootstrap allowed
→ logout, idle expiry, absolute expiry, password reset, or process stop
→ session invalid / dashboard locked
```

Every HTTP request terminates as a response. Authentication adds no background execution.

## Explicitly out of scope

- LAN, wildcard, or non-loopback binding.
- Plaintext-HTTP remote access.
- TLS certificates, reverse proxies, VPN configuration, or trusted-proxy headers.
- Persistent services, systemd units, daemonization, automatic restart, or boot startup.
- Multiple users, family accounts, permissions, invitations, or sign-ups.
- Storing a password, derived hash, salt, session token, or cookie in Git, `.env`, logs, HTML, JavaScript, URLs, or application-facade envelopes.
- Browser local storage or session storage for credentials or bearer tokens.
- Treating possession of a dashboard session as approval for destructive Soul operations; all existing human gates remain intact.

## LAN readiness boundary

Authentication is necessary but not sufficient for LAN exposure. Before the bind-host validator is widened, a separate approved transport brief must provide HTTPS or a comparably protected access path, safe host/origin configuration, secure cookies, deployment and recovery behavior, and deterministic remote-boundary tests. The server must continue rejecting LAN addresses until that work is reviewed.

## Human review checklist

- Confirm the blurred locked presentation matches the intended first-visit experience.
- Confirm the bootstrap credential never reveals dashboard data before replacement.
- Confirm the new password is not stored or returned in plaintext.
- Confirm refresh preserves a valid session and logout immediately locks the UI.
- Confirm password change revokes prior sessions.
- Confirm existing skill, memory, deletion, and approval gates are unchanged.
- Confirm LAN binding and persistence remain unavailable in this slice.
