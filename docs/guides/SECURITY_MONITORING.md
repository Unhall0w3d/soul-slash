# Security Monitoring

Soul's security lane combines Wazuh central observability with selective
ClamAV scanning. It is optional, single-Operator infrastructure and is not
installed by ordinary `make setup`.

## Division of responsibility

**Wazuh Dashboard** is the complete investigation console for agents, alerts,
vulnerabilities, system inventory, and security analytics.

**Soul Administration → Security** is a later read-only operational summary.
It will show bounded health and alert evidence and deep-link into Wazuh. It will
not duplicate the investigation console or give the model administrative
credentials.

**ClamAV** will scan only approved ingress and staging paths. It will not scan
model stores, generated media libraries, VM disks, or encrypted backup blobs by
default.

## Rollout stages

1. Security A0 — architecture, trust, retention, and response boundaries.
2. Central A1 — dedicated manager/indexer/dashboard with no agents.
3. Agent A2 — one passive endpoint pilot, then measured expansion.
4. ClamAV A3 — bounded manual ingress scan and Wazuh log collection.
5. Soul A4 — least-privilege read-only Security dashboard and invocation.

Each stage has a separate review. Installing the central platform does not
authorize agent enrollment, scanning, quarantine, or remediation.

## A1 central requirements

- supported 64-bit Linux guest, with Ubuntu Server 24.04 recommended;
- 4 vCPU, 8 GiB fixed RAM, and at least 50 GiB storage;
- reviewed private-LAN identity and key-only administration;
- private firewall allowing dashboard access and exact owner administration;
- official Wazuh 4.14 installer with root-only captured output;
- matched component versions and disabled post-install package repository;
- post-install reboot and recovery verification.

Owner-specific addresses, credentials, keys, and certificates belong in
ignored local state. See the [A0 architecture](../soul/WAZUH_CLAMAV_SECURITY_A0_BRIEF.md)
and [A1 central contract](../soul/WAZUH_CENTRAL_A1_BRIEF.md).

## Current interaction boundary

At A1, open the private Wazuh HTTPS URL and log in using the generated
administrator credential retained on the central guest. A browser warning is
expected for the initial self-signed certificate.

No Soul Chat or Voice security invocation exists yet. Do not paste Wazuh
credentials or alert payloads into Chat. The A4 integration will use a separate
read-only API identity and bounded response projection.

## Safe interpretation

A Wazuh alert is evidence requiring investigation, not proof that malware or an
intrusion occurred. A clean ClamAV scan is not proof that a file is safe. Soul
may summarize provenance and uncertainty, but the Operator remains the security
decision-maker.
