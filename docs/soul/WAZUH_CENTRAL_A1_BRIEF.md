# Wazuh Central A1 Brief

## Status

```text
human_architecture_approval: 2026-08-01
central_deployment_authorized: yes
endpoint_agent_enrollment_authorized: no
clamav_installation_authorized: no
soul_api_integration_authorized: no
automatic_response_authorized: no
human_live_review_required: yes
```

## Purpose

Deploy and qualify one private-LAN, single-node Wazuh central platform under the
approved Security A0 architecture. A1 establishes the manager, indexer, and
dashboard only. It does not enroll an endpoint, open agent ports, install
ClamAV, or grant Soul API credentials.

## Portable deployment contract

The central guest must provide:

- Ubuntu Server 24.04 LTS on x86-64;
- 4 fixed vCPU and 8 GiB fixed RAM;
- at least 50 GiB storage, with 60 GiB recommended for the pilot;
- one reviewed static or DHCP-reserved private-LAN identity;
- key-only owner administration;
- working time synchronization and DNS;
- a supported systemd environment.

The hypervisor, VM identifier, address, hostname, SSH key, and local DNS record
are owner-local values and must not enter tracked configuration.

Use the released Ubuntu cloud image, verify it against the matching official
SHA-256 manifest, and retain only the public release/hash evidence. Do not trust
an unverified daily or third-party image.

## Wazuh installation

Use the official Wazuh 4.14 assisted installation channel and validate the
downloaded shell before execution. Capture installation output in a root-owned
mode-0600 log because it contains generated credentials. Successful
installation is insufficient until all installed Wazuh components report the
same major/minor/patch version.

The central services intentionally persist and start at boot:

- `wazuh-indexer.service`;
- `wazuh-manager.service`;
- `wazuh-dashboard.service`;
- `filebeat.service`.

After installation, disable the Wazuh package repository as recommended by the
vendor. Upgrades become a separately reviewed matched-component maintenance
operation rather than part of ordinary unattended package maintenance.

## Firewall and listener policy

The guest firewall defaults to deny incoming and allow outgoing. A1 permits:

- SSH only from the exact Operator workstation;
- Wazuh dashboard HTTPS from the reviewed private subnet;
- Wazuh server API only from the exact Operator workstation.

Ports 1514 and 1515 remain blocked until A2 approves the first agent. TCP 9200
must be loopback-bound and must remain unreachable from the LAN. Wazuh cluster,
Syslog, UDP agent, and public ports remain closed.

The generated self-signed dashboard certificate is acceptable for initial
private-LAN review. A trusted private certificate and exact hostname validation
are later hardening, not grounds for exposing the service through a public
reverse proxy.

## Credentials and secrets

Generated administrator, indexer, and API credentials remain only in the
root-owned Wazuh install archive on the central guest. They must not enter:

- Git;
- Codex output or retained transcripts;
- Project Timeline state;
- Dashboard configuration;
- shell history;
- public or private review artifacts.

The Operator may retrieve the initial dashboard credential through an
interactive local terminal. A later Soul API identity must be distinct and
least-privilege; A1 does not create it.

## Initial retention

Create one 30-day Index State Management policy for time-series:

- `wazuh-alerts-*`;
- `wazuh-monitoring-*`;
- `wazuh-statistics-*`.

Attach it to current matching indices and supply an ISM template for future
matching indices. Vulnerability and inventory state indices are not deleted by
this policy. Raw local Wazuh log rotation and central-node backup remain later
measured work.

## Verification and acceptance

A1 must prove:

- verified Ubuntu source image;
- exact central resource allocation;
- key-only owner access;
- matched Wazuh component versions;
- active manager, indexer, dashboard, and Filebeat;
- indexer authentication and loopback-only listener;
- dashboard private-LAN reachability;
- unauthenticated API requests are rejected;
- exact firewall rules and blocked agent ports;
- disabled Wazuh package repository;
- attached 30-day policy;
- no failed systemd units;
- successful post-install reboot with changed boot identity;
- service and dashboard recovery after reboot;
- no committed owner-local identity or secret.

After verification, hypervisor deletion protection may be enabled. Runtime
evidence is recorded in an ignored owner-private receipt and the candidate ends
`blocked_for_human_review` until the Operator logs in and reviews the central
dashboard.

## Rollback

Before agents exist, rollback may stop the VM and use the official Wazuh
uninstall path or remove the protected VM after a separate exact human action.
Deletion protection must not be silently disabled. Rollback must not remove or
alter any existing fleet member, DNS service, backup repository, Soul service,
or firewall policy outside the central guest.

## Excluded from A1

- endpoint agents and agent ports;
- Active Response;
- ClamAV and scans;
- Soul API credentials or Dashboard code;
- alert acknowledgement or remediation;
- email, webhooks, or external notification;
- Internet exposure;
- raw-index backup, snapshot, or restore;
- automatic Wazuh upgrades.
