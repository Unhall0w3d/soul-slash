# Wazuh Arch Agent A2B Brief

## Status

```text
operator_activation_approval: 2026-08-02
aur_package_preinstalled_by_operator: yes
persistent_agent_service_approved: yes
endpoint_scoped_event_firewall_rule_approved: yes
temporary_enrollment_rule_approved: yes
active_response_approved: no
automatic_aur_upgrade_trust: no
```

## Purpose

Enroll one Operator-owned Arch-family workstation as a passive Wazuh endpoint
without broadening the manager firewall, granting remote response authority, or
treating an AUR recipe as equivalent to a distribution-supported package.

## Package trust boundary

The Operator installed the AUR `wazuh-agent` package. The reviewed recipe wraps
a checksum-pinned Wazuh RPM and adds an Arch configuration, an Arch SCA policy,
and bounded compatibility patches. It is still community packaging: pacman
reports no package signature or recognized packager.

Qualification is pinned to the reviewed recipe hashes and exact live version
pair. A later AUR update requires another recipe/source review before upgrade.
Soul does not install or automatically upgrade this package.

The manager may be newer than the agent, but the agent must never be newer than
the manager. Version lag is visible evidence, not silently normalized.

## Network and enrollment boundary

- Permit TCP 1514 on the manager from the exact workstation address only.
- Permit TCP 1515 from that address only while enrollment is occurring.
- Remove the 1515 rule immediately after successful enrollment.
- Do not add an inbound workstation firewall rule; the agent initiates the
  encrypted connection.
- Preserve the existing private dashboard and read-only API boundaries.

## Endpoint boundary

- Enroll one exact workstation identity.
- Configure the exact private manager endpoint.
- Set endpoint-side Active Response to disabled before starting the agent.
- Restrict agent configuration and enrollment-key files to the agent identity.
- Enable and start only `wazuh-agent.service`.
- Do not grant Active Response, command execution, automatic remediation, or
  arbitrary root authority.

## Verification

- installed recipe and source checksums are reviewed;
- manager version is greater than or equal to agent version;
- agent service is enabled and active;
- manager reports the exact endpoint Active;
- the endpoint holds an established TCP 1514 connection;
- temporary TCP 1515 access is absent;
- Active Response remains disabled;
- agent configuration and key files are mode `0640`;
- no secret, private address, or enrollment key enters tracked evidence.

## Rollback

Disable and stop the exact agent service, remove the exact endpoint from the
manager through a separately reviewed operation, and remove its endpoint-only
TCP 1514 firewall rule. Do not delete local agent evidence or configuration as
part of an automatic rollback.
