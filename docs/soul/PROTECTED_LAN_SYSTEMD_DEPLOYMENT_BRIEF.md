# Approved Brief: Protected LAN and Persistent Local Dashboard

```text
brief_status: approved by human owner instruction
implementation_authorized: yes
target: current local Linux machine
proxmox_target: no
persistent_services_authorized: exactly two user services
lan_listener_authorized: Caddy HTTPS only
soul_lan_bind_authorized: no
human_deployment_review_required: yes
human_merge_review_required: yes
```

The human owner approved this local persistent deployment on 2026-07-15 after completing the forced-change dashboard authentication flow. This brief is the explicit narrow exception required by `AGENTS.md` for persistent services and a LAN listener.

## Purpose

Keep the authenticated Soul dashboard available after logout and reboot on the current Linux machine, and make it reachable from trusted LAN devices through encrypted HTTPS.

## Risk class

```text
Class 5: persistent service, LAN network listener, TLS trust, and private runtime access
```

## Approved architecture

```text
trusted LAN browser
→ Caddy user service on exact configured LAN address, TCP 8443, HTTPS only
→ Soul dashboard user service on 127.0.0.1:4567, HTTP loopback only
→ shared application facade and existing approval gates
```

The approved implementation may add and enable exactly these user services:

- `soul-dashboard.service`
- `soul-dashboard-proxy.service`

The existing systemd user manager and user lingering may be used. No root-owned Soul service is authorized. No container, Proxmox guest, cron job, timer unit, socket-activation unit, watcher, or additional background process is authorized.

## Caddy exception

Caddy may remain running as the second user service to terminate TLS and reverse proxy to Soul. It may maintain its internal certificate authority and renew its local leaf/intermediate certificates as part of that approved service. The Caddy admin API, automatic HTTP redirect listener, active health checks, HTTP/3, remote ACME, telemetry, and on-demand TLS are disabled or unused.

The initial deployment uses unprivileged TCP port `8443`; it does not grant `CAP_NET_BIND_SERVICE`, bind port 80/443, or run Caddy as root. Caddy must bind the exact configured LAN address rather than a wildcard address.

## Portable configuration

Tracked files contain no owner IP address, username, home path, certificate, credential, or generated unit. The opt-in installer renders local files beneath:

```text
~/.config/soul/dashboard.env
~/.config/soul/Caddyfile
~/.config/systemd/user/soul-dashboard.service
~/.config/systemd/user/soul-dashboard-proxy.service
~/.local/share/caddy/
```

`dashboard.env` is owner-only and contains the exact HTTPS public origin. Existing provider/model values continue to resolve from the ignored project `.env`.

## Required gates

The installer must terminate `blocked_for_human_review` or fail without enabling services unless all conditions pass:

- the target is Linux with a usable systemd user manager;
- Caddy is already installed from an operator-approved source;
- the Soul project root and Ruby executable are absolute and present;
- the LAN bind value is one exact non-loopback IPv4 address assigned to this host;
- HTTPS port is between 1024 and 65535 and is not Soul's loopback port;
- the dashboard credential exists, is owner-only, and no longer requires bootstrap password replacement;
- Caddy validates the rendered Caddyfile before service installation;
- rendered unit and environment files contain no password, derived password hash, session token, model credential, or `.env` content;
- Soul's own `dashboard.bind_host` remains loopback-only;
- the exact configured HTTPS origin is the only additional accepted Host/Origin authority;
- remote authentication cookies carry `Secure`, `HttpOnly`, and `SameSite=Strict`.

## Service lifecycle

Each service has explicit `start`, `complete/active`, `failed`, `stop/canceled`, and human-review behavior through systemd and the installer result. Restart policy is `on-failure` with a bounded systemd start-rate limit. Soul and Caddy do not implement their own retry or polling loops.

Installation and removal are foreground commands. The installer may render files, reload the user manager, and enable/start the two exact services after all gates pass. The uninstaller may disable/stop only those services and remove only the rendered unit/config files. It must preserve credentials, chats, memory, Caddy CA state, and other private runtime data unless the human explicitly removes them separately.

## TLS and device trust

Caddy uses `tls internal`. Client devices must install and explicitly trust the generated Soul deployment root CA before using the LAN URL. The private CA key never leaves the host. Only the public root certificate may be copied to client devices.

The repository and installer must not silently weaken certificate validation. Browser certificate warnings are not an acceptable steady-state workflow.

## Explicitly out of scope

- Internet exposure, router port forwarding, UPnP, public DNS, public ACME, or cloud tunnels.
- Wildcard Soul binding or direct LAN access to port 4567.
- Plaintext LAN HTTP.
- Port 80 or 443, privileged capabilities, or root-run application processes.
- Multiple accounts, family sign-ups, authorization roles, or password sharing policy.
- Automatic firewall changes, router changes, DHCP reservations, DNS changes, or client certificate installation.
- Automatic repository pulls, dependency upgrades, package upgrades, database migrations, backups, or recovery jobs.
- Applying a model-generated IP address or service configuration without deterministic validation.

## Rollback

```text
disable and stop soul-dashboard-proxy.service
disable and stop soul-dashboard.service
remove rendered user unit files and local non-secret proxy/environment configuration
reload the user manager
preserve Soul/runtime and Caddy PKI state
return to explicit ruby bin/soul dashboard loopback operation
```

## Human review checklist

- Confirm the HTTPS URL is reachable from this machine with certificate validation enabled.
- Install the public Caddy root CA on one chosen client device and confirm the browser shows a trusted connection.
- Confirm unauthenticated LAN access remains blurred and application calls return `401`.
- Confirm the changed administrator password authenticates successfully over HTTPS.
- Confirm cookies include `Secure`, `HttpOnly`, and `SameSite=Strict`.
- Confirm direct LAN access to port 4567 fails while loopback access remains available locally.
- Confirm both services restart after a deliberate process failure without exceeding rate limits.
- Confirm logout revokes its session, while restart preserves only unexpired owner-approved seven-day digest-backed sessions.
- Confirm uninstall returns to foreground loopback operation without deleting private data.
- Confirm no router or Internet exposure exists.
