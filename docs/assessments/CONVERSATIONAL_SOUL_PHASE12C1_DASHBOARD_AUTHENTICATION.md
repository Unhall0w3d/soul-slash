# Conversational Soul Phase 12C.1 Dashboard Authentication Review

## What was implemented

- Added one fixed personal administrator account named `admin` with no sign-up or account-creation surface.
- Added a first-run `soul123` bootstrap password that can create only a password-change-required session.
- Required a 12–128 character replacement password before the application facade, conversations, workspace, Skill Studio, or Self Improvement data can load.
- Stored only a salted PBKDF2-HMAC-SHA256 derived password record under ignored local runtime storage.
- Added bounded in-memory sessions, host-only cookies, idle and absolute expiry, failed-login throttling, logout, and session revocation after password change or local reset.
- Added a blurred, inert dashboard backdrop with accessible login and first-password-change overlays.
- Kept the listener loopback-only and foreground-only. LAN binding, TLS, and service persistence remain separate review gates.

## Files changed

- `assets/dashboard/index.html`
- `assets/dashboard/dashboard.css`
- `assets/dashboard/dashboard.js`
- `docs/soul/PHASE12C1_DASHBOARD_AUTHENTICATION_BRIEF.md`
- `docs/assessments/CONVERSATIONAL_SOUL_PHASE12C1_DASHBOARD_AUTHENTICATION.md`
- `lib/soul_core/dashboard_authentication.rb`
- `lib/soul_core/dashboard_authentication_assessor.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/dashboard_server.rb`
- `lib/soul_core/dashboard_command.rb`
- `lib/soul_core/phase12c_foreground_dashboard_assessor.rb`
- `lib/soul_core/app.rb`
- `scripts/verify-dashboard-authentication-phase12c1.rb`
- `scripts/verify-runtime-privacy-hygiene-phase44.rb` (allows only the established tracked `Soul/runtime/.keep` placeholder while continuing to reject real runtime data)

Documentation and the previously candidate Soul micro-mark are included in the same working branch but remain independently reviewable in Git.

## Commands run

```text
ruby -c lib/soul_core/dashboard_authentication.rb
ruby -c lib/soul_core/dashboard_http_application.rb
ruby -c lib/soul_core/dashboard_authentication_assessor.rb
ruby -c lib/soul_core/dashboard_command.rb
ruby -c lib/soul_core/app.rb
ruby bin/soul assess dashboard-authentication --json
ruby bin/soul assess dashboard-authentication
ruby scripts/verify-phase12c-foreground-dashboard.rb
ruby scripts/verify-dashboard-authentication-phase12c1.rb
git diff --check
git diff --cached --check
```

## Deterministic test results

The dedicated assessor covers:

- owner-only hashed bootstrap credential creation;
- generic invalid-login behavior and bounded rate limiting;
- origin, content-type, and CSRF rejection;
- anonymous and bootstrap-session denial at the application facade;
- password policy, replacement, credential rotation, and old-session revocation;
- successful facade delegation only after password replacement;
- logout, cookie expiry, idle session expiry, and explicit local reset;
- blurred/inert DOM behavior, absence of client-side credential stores, unchanged human approval gates, and continued LAN/persistence prohibition.

The legacy Phase 12C foreground-dashboard verifier remains a required regression. Final results are recorded when the aggregate verifier is run after implementation.

## Local LLM eval results

Not run. Authentication correctness and safety are not delegated to an LLM. Human-facing wording is reviewed directly in the local dashboard.

## Known weaknesses

- Authentication is single-user and intentionally has no account recovery workflow. A person with local operating-system access may explicitly reset the administrator to the bootstrap credential with `ruby bin/soul dashboard --reset-admin-password`.
- Sessions are process-local and are lost when the foreground dashboard restarts. This is a deliberate fail-closed posture for the current architecture.
- The current loopback HTTP cookie cannot use `Secure`. LAN exposure remains blocked until HTTPS or a comparably protected transport is separately approved.
- The public bootstrap password is intentionally known and provides no dashboard-data access until it is replaced. A future LAN/service installer must refuse startup if the bootstrap gate is still active.
- Authentication does not replace Soul's operation-specific confirmation, destructive-action, memory, skill, or human-review gates.

## Memory keys

None. Dashboard credentials are authentication state under ignored `Soul/runtime/`, not Soul conversational memory.

## Task lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

Every request terminates synchronously. No background wait state, timer, watcher, or continuation was added.

## Risk classification

```text
Class 5: security-sensitive authentication and private-runtime credential storage
```

The implementation follows the reviewed PBKDF2-HMAC-SHA256 work factor and uses host-only `HttpOnly`/`SameSite=Strict` cookie boundaries. Passwords and bearer tokens are excluded from Git, `.env`, DOM storage, URLs, logs, and facade envelopes.

Reference material reviewed during implementation:

- OWASP Password Storage Cheat Sheet: PBKDF2-HMAC-SHA256 baseline and work-factor guidance.
- Ruby OpenSSL KDF documentation: standard-library PBKDF2 API.
- MDN secure cookie and session-management guidance: `HttpOnly`, `SameSite`, host-only scope, and the requirement for HTTPS before `Secure` remote cookies.

## Human review checklist

- [x] First visit shows a recognizable but blurred and inert dashboard behind the login overlay.
- [x] `admin` / `soul123` proceeds only to forced password replacement.
- [ ] A short, mismatched, unchanged, or bootstrap replacement password is rejected clearly.
- [x] A valid replacement unlocks and loads the dashboard.
- [ ] Refresh preserves the active process-local session.
- [ ] Logout clears dashboard data from view and returns to the locked presentation.
- [ ] Reset command restores the forced-change bootstrap state without starting a listener.
- [ ] Existing destructive and human approval gates still appear and behave unchanged after login.
- [ ] LAN binding remains rejected.
- [ ] No authentication value appears in Git status or tracked files under `Soul/runtime/`.

## Human review outcome

The owner completed the first-login flow on 2026-07-15, replaced the bootstrap password, confirmed that the authenticated dashboard loaded successfully, and described the experience as working well. The remaining logout, reset, approval-gate regression, LAN rejection, and repository-privacy checklist items stay open until explicitly exercised or reviewed.

This records authentication-flow and visual acceptance only. It does not imply approval to merge, expose on the LAN, or install a persistent service.
