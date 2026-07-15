# Local systemd and LAN HTTPS Deployment

This deployment keeps Soul itself on loopback and places a Caddy-managed HTTPS endpoint on one exact address assigned to the current Linux machine.

```text
LAN browser → https://<assigned-ip>:8443 → Caddy → http://127.0.0.1:4567 → Soul
```

It is opt-in. Cloning or running Soul does not install, enable, or start a service.

## Prerequisites

- Linux with a working systemd user manager.
- User lingering enabled so the user manager starts at boot.
- Caddy installed from a source approved by the operator.
- Completed dashboard first-login password replacement.
- One stable IPv4 LAN address assigned to the machine. A DHCP reservation is recommended but is not created by Soul.
- TCP port `8443` reachable from the trusted LAN. Soul does not alter the host firewall or router.

On Arch/CachyOS, Caddy is available in the official `Extra` repository: `sudo pacman -S caddy`. Package installation remains an explicit operator action. Check lingering with `loginctl show-user "$USER" -p Linger`; if needed, enable it deliberately with `sudo loginctl enable-linger "$USER"`.

## Preview

Use the machine's exact assigned LAN address:

```bash
make dashboard-service-plan LAN_HOST=192.168.1.50
```

The plan validates the address, port, Caddy and systemd executables, administrator credential state, exact rendered paths, and rollback boundary. It writes nothing and returns `blocked_for_human_review` with the confirmation phrase.

## Install

After reviewing the exact plan:

```bash
make dashboard-service-install \
  LAN_HOST=192.168.1.50 \
  CONFIRM=INSTALL_SOUL_LAN_SERVICES
```

The foreground installer validates the generated Caddyfile before writing local files, renders owner-only configuration, reloads the user manager, and enables exactly:

```text
soul-dashboard.service
soul-dashboard-proxy.service
```

If service activation fails, both services are disabled and stopped. Private data and rendered reviewable configuration are preserved for diagnosis.

## Local files

```text
~/.config/soul/dashboard.env
~/.config/soul/Caddyfile
~/.config/systemd/user/soul-dashboard.service
~/.config/systemd/user/soul-dashboard-proxy.service
~/.local/share/caddy/
```

The environment file contains only the loopback bind, loopback port, and exact public HTTPS origin. Existing provider/model configuration remains in the ignored project `.env`.

To use a different unprivileged HTTPS port in the plan and install targets, set `DASHBOARD_HTTPS_PORT=<port>` on both Make invocations. Machine-specific values are invocation-only and are not committed.

## Status and logs

```bash
make dashboard-service-status
make dashboard-service-logs
systemctl --user status soul-dashboard.service soul-dashboard-proxy.service
journalctl --user -u soul-dashboard.service -u soul-dashboard-proxy.service --no-pager
```

There is no application polling loop. systemd applies `Restart=on-failure` with a bounded start-rate limit.

## Device certificate trust

Caddy uses its internal CA. After the proxy starts, its public root certificate is expected at:

```text
~/.local/share/caddy/pki/authorities/local/root.crt
```

Copy only `root.crt` to each selected client and install it as a trusted root/CA certificate using that operating system's certificate settings. Never copy the adjacent private key. After trust is installed, open the exact configured HTTPS URL and require the browser to show a valid encrypted connection without a certificate warning.

For convenient manual transfer, the operator may make a public-certificate copy such as `install -m 0644 ~/.local/share/caddy/pki/authorities/local/root.crt ~/Downloads/soul-local-ca.crt`. This command must never target the adjacent private key.

Installing a private CA grants it trust on that device. Restrict the Caddy state directory to the Soul host and remove the CA from client devices if this deployment is retired.

## Security boundary

- Soul continues rejecting wildcard and LAN bind addresses.
- Only the configured HTTPS Host and Origin are added to the browser allowlist.
- Remote session cookies are `Secure`, `HttpOnly`, `SameSite=Strict`, and host-only.
- Caddy's admin API, automatic HTTP redirect listener, HTTP/3, active health checking, remote ACME, and on-demand TLS are not used.
- The deployment does not change router, DNS, DHCP, firewall, or Internet exposure.
- Authentication does not replace Soul's destructive-action, skill, memory, or approval gates.

If UFW uses a default-deny incoming policy, add only a narrow trusted-subnet rule after reviewing the actual interface address and CIDR:

```bash
sudo ufw allow from <trusted-lan-cidr> to <assigned-lan-ip> port 8443 proto tcp comment 'Soul dashboard LAN HTTPS'
```

Avoid a global `ufw allow 8443` rule. Do not configure router forwarding or expose this private-CA endpoint to the Internet.

## Uninstall and rollback

```bash
make dashboard-service-uninstall CONFIRM=REMOVE_SOUL_LAN_SERVICES
```

This stops and disables only the two Soul user services and removes their rendered unit/environment/Caddy configuration. It preserves:

```text
Soul/runtime/
~/.local/share/caddy/
```

The dashboard can then return to explicit foreground loopback operation:

```bash
make dashboard
```

Remove the preserved Caddy PKI or trusted client root certificates only through a separate deliberate cleanup decision.
