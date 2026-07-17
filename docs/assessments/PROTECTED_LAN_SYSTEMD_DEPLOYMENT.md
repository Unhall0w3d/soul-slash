# Protected LAN and systemd Deployment Review

## What was implemented

- Added one optional exact HTTPS public-origin setting while retaining Soul's loopback-only bind validator.
- Added exact public Host/Origin validation and `Secure` cookies only for requests arriving through the configured HTTPS authority.
- Added a preview-first portable installer for exactly two user services: the Soul dashboard and a Caddy HTTPS reverse proxy.
- Added Caddy internal TLS on an exact assigned IPv4 address and unprivileged port `8443`.
- Disabled the Caddy admin API, automatic HTTP redirect listener, HTTP/3, remote ACME, on-demand TLS, and active health checks.
- Added bounded systemd restart policies, owner-only rendered files, deterministic prerequisite gates, rollback, status, and uninstall behavior.
- Corrected dashboard hardening to permit `AF_UNIX` for bounded communication
  with the existing systemd user manager. IPv4/IPv6 listener policy is
  unchanged, and no additional service or socket is introduced.
- Added automatic page reload when an already-open dashboard presents the stale
  CSRF token left by a dashboard-service restart.
- Corrected reinstall behavior to enable and restart the same two approved
  services, ensuring changed unit hardening is applied rather than leaving the
  previous process restrictions active.
- Added Make targets for the complete preview, confirmed install, status, logs, and confirmed uninstall lifecycle.
- Documented Caddy and lingering prerequisites, first-login sequencing, narrow UFW access, public-CA transfer, client validation, and rollback.
- Kept machine paths, addresses, and generated certificate state out of Git.

## Files changed

- `.env.example`
- `Makefile`
- `lib/soul_core/configuration_schema.rb`
- `lib/soul_core/configuration_resolver.rb`
- `lib/soul_core/phase12a_portable_typed_configuration_assessor.rb`
- `lib/soul_core/dashboard_command.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/dashboard_deployment.rb`
- `lib/soul_core/dashboard_deployment_assessor.rb`
- `lib/soul_core/app.rb`
- `scripts/soul-dashboard-service`
- `scripts/verify-protected-lan-systemd-deployment.rb`
- `docs/soul/PROTECTED_LAN_SYSTEMD_DEPLOYMENT_BRIEF.md`
- `docs/soul/LOCAL_SYSTEMD_HTTPS_DEPLOYMENT.md`
- `docs/assessments/PROTECTED_LAN_SYSTEMD_DEPLOYMENT.md`
- supporting current-state, setup, roadmap, and changelog documentation

## Commands run

```text
ruby -c lib/soul_core/dashboard_deployment.rb
ruby -c lib/soul_core/dashboard_deployment_assessor.rb
ruby -c scripts/soul-dashboard-service
ruby bin/soul assess phase12a-configuration --json
ruby bin/soul assess dashboard-authentication --json
ruby bin/soul assess dashboard-deployment --json
ruby scripts/verify-protected-lan-systemd-deployment.rb
ruby scripts/verify-responsive-chat-and-web-research.rb
ruby scripts/verify-model-runtime-portability.rb
ruby scripts/verify-model-runtime-profile-switching.rb
ruby scripts/verify-phase12c-foreground-dashboard.rb
make help
make dashboard-service-plan
make dashboard-service-install
make dashboard-service-uninstall
scripts/soul-dashboard-service plan --lan-host <assigned-ip> --https-port 8443
scripts/soul-dashboard-service install --lan-host 192.168.124.238 --https-port 8443 --confirmation INSTALL_SOUL_LAN_SERVICES
scripts/soul-dashboard-service status
curl --cacert ~/.local/share/caddy/pki/authorities/local/root.crt https://192.168.124.238:8443/
curl --cacert ~/.local/share/caddy/pki/authorities/local/root.crt -H 'Origin: https://192.168.124.238:8443' -H 'Content-Type: application/json' -H 'X-Soul-CSRF: <page-token>' --data '<private-call>' https://192.168.124.238:8443/api/v1/call
curl http://127.0.0.1:4567/
curl --connect-timeout 3 http://192.168.124.238:4567/
openssl s_client -connect 192.168.124.238:8443 -CAfile ~/.local/share/caddy/pki/authorities/local/root.crt -verify_return_error
```

The 2026-07-16 refresh-health repair was applied through the same confirmed
installer. Live verification then reported both status operations `complete`,
host `maven`, model runtime `loaded`, service `active`, server health `ready`,
and idle state certain. Dashboard, proxy, and AMD model services were active;
certificate-validated LAN HTTPS returned HTTP 200 on the unchanged exact
address and port.

The first repair reinstall exposed a systemd semantic gap: `enable --now` left
the already-active dashboard process running under its earlier socket-family
restriction. A deliberate dashboard restart loaded `AF_UNIX`; the installer is
now regression-tested to enable and restart both exact approved services on
reinstall so rendered unit changes cannot remain dormant.

The corrected installation completed at `2026-07-15T21:48:13Z`. Both allowlisted user services became enabled and active. Live verification returned HTTP 200 through trusted HTTPS, HTTP 401 for an anonymous private API call after valid CSRF handling, HTTP 200 on Soul's loopback endpoint, and connection refusal for direct LAN access to Soul port `4567`.

## Deterministic test results

The deployment assessor verifies:

- wildcard, loopback, invalid, and unassigned addresses fail closed;
- privileged, colliding, invalid, and out-of-range ports fail closed;
- the valid plan returns `blocked_for_human_review` without writes;
- the bootstrap-password state blocks deployment;
- rendered configuration keeps Soul on `127.0.0.1:4567` and binds Caddy to one exact LAN address;
- generated files contain no password, password hash, session value, model credential, or project `.env` content;
- Caddy validation precedes rendered writes and service enablement;
- install and uninstall require exact confirmation;
- install enables only two services and uses bounded restart policies;
- failure rollback stops/disables both services;
- uninstall preserves Soul runtime data and Caddy PKI state;
- wrong public Hosts and Origins fail closed;
- the exact HTTPS origin receives a host-only `Secure`, `HttpOnly`, `SameSite=Strict` cookie;
- stale CSRF tokens from a service restart trigger a page reload rather than
  leaving status cards in a generic unavailable state;
- the dashboard unit permits Unix sockets required for `systemctl --user`
  inspection while retaining its existing loopback HTTP bind;
- prior configuration, authentication, dashboard, Skill Studio, Self Improvement, and privacy regressions remain green.

The authentication regression now recognizes the current single- and
multi-conversation permanent-deletion confirmation gates whether their literal
is rendered in static markup or by the bounded browser controller.

The first local activation attempt failed safely because systemd does not accept a quoted `WorkingDirectory=` value. Both services were rolled back before a LAN listener started. The renderer was corrected to use systemd path escaping, and a regression now rejects quoted working-directory output.

## Local LLM eval results

Not run. Network binding, TLS, authentication, persistence, path safety, and lifecycle correctness are deterministic and human-reviewed security decisions, not LLM evaluation targets.

## Known weaknesses

- The initial URL uses a LAN IP and port `8443`. If DHCP changes the address, Caddy fails closed until the local configuration is deliberately regenerated. A router-side DHCP reservation is recommended but not automated.
- Each client must explicitly trust the private Caddy root CA. This is manageable for personal devices but not a substitute for a public-domain certificate architecture.
- The installer does not alter the host firewall. A restrictive firewall may require a separate human-approved TCP `8443` rule for the trusted LAN.
- The installer uses the current repository path. Moving or deleting the checkout breaks the Soul service until it is reinstalled from the new path.
- Unexpired sessions survive service restart for at most seven days through owner-only token-digest records; credentials and private Soul data persist, while logout and credential changes revoke sessions.
- This deployment is LAN-only. It does not provide safe Internet exposure, public DNS, router forwarding, multi-user authorization, or account recovery.

## Memory keys

None. Service state, credentials, certificates, and machine configuration are operational state rather than Soul conversational memory.

## Task lifecycle states touched

- `complete`
- `failed`
- `awaiting_input`
- `canceled`
- `blocked_for_human_review`

The installer and uninstaller are bounded foreground commands. The two explicitly approved services persist through systemd and have observable active, failed, stopped, and restart-limited states.

## Risk classification

```text
Class 5: persistent service, LAN network listener, TLS trust, and private runtime access
```

Primary documentation reviewed:

- Caddy running-as-a-service and local-HTTPS documentation.
- Caddy `reverse_proxy` and `tls internal` documentation.
- Arch Linux official Caddy package metadata.
- ArchWiki systemd user lingering guidance.
- MDN secure-cookie guidance retained from the authentication phase.

## Human review checklist

- [x] Authentication bootstrap password was replaced before deployment planning.
- [x] Generated Caddyfile validates with installed Caddy `2.11.4`.
- [x] Both user services install, enable, and become active.
- [x] Soul remains reachable only on loopback port `4567`; direct LAN connection is refused.
- [x] Caddy listens on exact address `192.168.124.238` and TCP port `8443`.
- [x] Local HTTPS responds with a verified Caddy chain whose leaf SAN is exactly `192.168.124.238`.
- [x] The public root CA is installed on a selected client device.
- [x] The client browser reports a trusted HTTPS connection without bypassing a warning.
- [x] Anonymous LAN access stays blurred and private application calls return `authentication_required` with HTTP 401.
- [x] Administrator login works over HTTPS and the cookie is `Secure`.
- [x] Logout and service restart behave as documented.
- [x] No router, public Internet, wildcard bind, or plaintext LAN endpoint was created by this deployment.
- [x] UFW permits TCP `8443` only from the local `192.168.124.0/24` network to the exact dashboard address.
- [x] Uninstall/rollback boundary is understood before merge.

## Human review outcome

Local installation, host-side boundary review, client CA trust, administrator HTTPS login/logout, and the narrow LAN firewall rule passed human review on 2026-07-15. The human accepted this candidate for the protected local deployment scope. This approval does not authorize Internet exposure or router forwarding.
