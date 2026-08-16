# Fleet Historical Telemetry and Observability A1 Deployment Brief

Status: candidate deployment brief; exact owner-local installation requires the
Operator's explicit infrastructure approval.

## Purpose

A1 turns the accepted A0 architecture into one reproducible, bounded private-LAN
pilot. It does not give Soul monitoring-derived mutation authority. Grafana is
the human exploration surface; Wazuh remains the security authority.

## Exact central profile

The central stack runs in one dedicated unprivileged Debian Linux container on
an owner-selected hypervisor. Owner-local configuration supplies the container
ID, hostname, static address, gateway, resolver, search domain, and SSH key.
Those private values do not enter the public repository.

The fixed resource profile is:

- 2 vCPUs;
- 3,072 MiB fixed memory plus 512 MiB emergency swap;
- 8 GiB root volume;
- 36 GiB dedicated Prometheus volume; and
- 20 GiB dedicated Loki volume.

The guest may start with its hypervisor. No Docker nesting, privileged container,
host-device passthrough, or shared host path is allowed.

## Services and network boundary

The central guest installs pinned or package-managed Prometheus, Loki, Grafana,
and Caddy. Prometheus and Loki bind only to loopback. Caddy is the only LAN-facing
listener and exposes HTTPS on port 443. Grafana requires its own login. Metrics
ingest requires separate basic authentication over the Caddy-managed internal
TLS certificate. There is no public ingress, anonymous Grafana access, or direct
LAN access to Prometheus or Loki.

The internal CA certificate and ingest secret are owner-private deployment
material. They are distributed only to explicitly enrolled collectors, stored
root-readable on disk, and never committed, logged, displayed by the Dashboard,
or copied into Soul memory. The central guest retains one mode-`0600` bootstrap
credential file so the Operator can enroll collectors and save the initial
Grafana credential in their password manager; plaintext Grafana bootstrap data
may be removed after that handoff, while the active ingest secret remains
required until it is deliberately rotated.

## Collection pilot

The first wave retains A0's four roles: Operator workstation, primary
hypervisor, secondary hypervisor, and backup target. A pinned Grafana Alloy
binary runs as a dedicated unprivileged service account and forwards only the
reviewed Unix exporter metrics with four stable labels: `device_id`, `role`,
`platform`, and `environment`.

Raw journal ingestion is deliberately disabled in A1. The general kernel and
service journal is too broad for A0's privacy exclusions. Loki is installed and
retention-bound, but it receives no endpoint journal until a follow-up review
defines exact per-platform selectors and proves that credentials, command lines,
authentication records, application bodies, paths, and private Soul content
cannot enter the lane.

## Retention and storage

Prometheus retains at most 30 days and 28 GB, below 80 percent of its 36 GiB
volume. Loki retention is fixed at 336 hours and its physical volume is capped at
20 GiB. Raw metrics and logs remain excluded from Restic/DRS. Reviewed service
configuration, dashboards, and rules may be backed up as reproducible config.

## Lifecycle and rollback

The deployment is complete only when all central services are active after a
guest reboot, HTTPS and authentication are proven, enrolled targets are fresh,
and storage limits are visible. Failure leaves the guest stopped for review; it
does not delete or recreate an existing guest automatically.

Collector rollback disables and removes only the reviewed Alloy service,
binary, configuration, CA, and owner-private credential. Central rollback stops
and removes only the dedicated guest and its owned volumes after a separate
inventory review. Wazuh, Soul, fleet maintenance, DNS, backups, and unrelated
guests are outside rollback authority.

## Explicit exclusions

- no automatic remediation or endpoint command execution;
- no Soul query adapter or Incident Narrator adapter in A1;
- no alerts, paging, or notification routing;
- no SNMP or Proxmox API integration;
- no raw Wazuh data or authentication logs;
- no automatic collector discovery or enrollment;
- no telemetry backup; and
- no automatic guest deletion, volume deletion, or rollback.

## Acceptance

- the unprivileged guest matches the fixed resource and volume profile;
- only HTTPS 443 is exposed to the private LAN;
- Prometheus and Loki are loopback-only;
- Grafana and ingest both reject unauthenticated access;
- Prometheus shows fresh metrics for every enrolled pilot role;
- retention and physical volume caps match this brief;
- a reboot restores the central services and collectors reconnect;
- no raw journal stream exists;
- the public tree contains no private address, credential, certificate, key, or
  owner-specific identity; and
- the Operator performs the final visual and operational review.

## A1.1 management-plane amendment

The later Operator-approved full-management enrollment adds SSH TCP 22 as a
management-plane exception. It is key-only, non-root, and the enrolled account
has passwordless root authority only for the digest-bound `self-check`,
`apt-upgrade`, and `reboot` helper vectors. HTTPS 443 remains the only
application-facing listener; Prometheus, Loki, and Grafana remain loopback-only.
