# Wazuh Arch Agent A2B Review

## Status

Live-qualified for one Operator workstation, with AUR maintenance risk retained
as explicit evidence.

## Live result

- A community Arch package based on Wazuh agent `4.14.6` is installed.
- The central manager is `4.14.7`; the supported manager-newer-than-agent
  direction is preserved.
- The AUR recipe's agent payload is the upstream Wazuh RPM protected by an
  explicit SHA-512 checksum. The recipe also supplies a checksummed Arch
  configuration, Arch SCA policy, and narrow Arch-derivative SCA patches.
- Pacman reports the locally built package as unsigned and from an unknown
  packager. Future recipe changes require review before upgrade.
- The endpoint is enrolled, enabled, active, and reported Active by the manager.
- Manager TCP 1514 is allowed only from the exact endpoint. Temporary TCP 1515
  enrollment access was removed after enrollment.
- The endpoint has an established manager connection and no inbound agent port.
- Active Response is disabled in the endpoint configuration.
- Agent configuration and enrollment-key permissions were normalized to mode
  `0640` after review found the AUR fresh-install hook looser than its own
  upgrade hook.

## Commands and evidence

- `pacman -Qi wazuh-agent`
- review of cached `PKGBUILD`, `.SRCINFO`, install hook, Arch config, SCA patch,
  and source checksum
- `systemctl is-enabled wazuh-agent`
- `systemctl is-active wazuh-agent`
- manager `agent_control -lc`
- manager firewall status after temporary-rule removal
- endpoint connection census for TCP 1514

Raw addresses, enrollment material, firewall output, and local recipe paths are
owner-private and excluded from Git.

## Known weaknesses

- The AUR package trails the manager by one patch release.
- An AUR package is owner-maintained community packaging, not an official Wazuh
  Arch package. Recipe and source changes must be re-reviewed.
- Wazuh agent activity does not prove every desired log or ClamAV receipt is
  ingested; those are separate decoder/evidence gates.
- Active Response remains intentionally unavailable.

## Risk classification

Persistent passive endpoint telemetry over one endpoint-scoped private-LAN
channel. Remote mutation and automatic response are excluded.

## Human review checklist

- [x] Approve enrollment and persistent agent activation.
- [x] Approve exact endpoint-scoped TCP 1514 manager access.
- [x] Approve temporary TCP 1515 enrollment access and confirm its removal.
- [x] Confirm Active Response remains disabled.
- [x] Record the AUR version lag and owner-maintained update boundary.
