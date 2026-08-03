# Security Monitoring

Soul's security lane combines Wazuh central observability with selective
ClamAV scanning. It is optional, single-Operator infrastructure and is not
installed by ordinary `make setup`.

## Division of responsibility

**Wazuh Dashboard** is the complete investigation console for agents, alerts,
vulnerabilities, system inventory, and security analytics.

**Soul Guided Maintenance and Administration → Local Topology** carry the
read-only operational projection. A4a shows manager and endpoint-agent health
on the associated system cards and deep-links into Wazuh. It does not duplicate
the investigation console or give the model administrative credentials.
Alert evidence uses the separately qualified A4b lane: a restricted SSH tunnel
preserves the indexer's loopback-only bind, and a dedicated indexer role can
search only `wazuh-alerts-*`. Soul stores bounded normalized evidence, not raw
events, and still cannot acknowledge, suppress, write, or remediate alerts.

**ClamAV** will scan only approved ingress and staging paths. It will not scan
model stores, generated media libraries, VM disks, or encrypted backup blobs by
default.

The current A3 design uses standalone `clamscan`, not the resident daemon or
on-access scanner. Official signatures update once daily through the packaged
`clamav-freshclam-once.timer`; file scans remain explicit foreground actions.

## Rollout stages

1. Security A0 — architecture, trust, retention, and response boundaries.
2. Central A1 — dedicated manager/indexer/dashboard with no agents.
3. Agent A2 — one passive endpoint pilot, then measured expansion.
4. ClamAV A3 — bounded manual ingress scan and Wazuh log collection.
5. Soul A4a — least-privilege server-API health on Maintenance cards and Local Topology.
6. Soul A4b — bounded read-only indexer alert evidence through a restricted tunnel.
7. Soul A4c — durable high-priority cursor and optional static voice notification.
8. Soul A4d — owner-reviewed workstation interpretation beside the unchanged raw Wazuh SCA result.

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

## A2 passive endpoint requirements

- install one exact signed agent matching the central release;
- restrict registration and event transport to the exact endpoint;
- close registration immediately after enrollment;
- disable the package repository after installation;
- explicitly disable endpoint Active Response;
- measure startup and settled resource cost before adding another endpoint;
- retain exact endpoint evidence only in ignored owner-local receipts.

The first Fedora pilot is machine-qualified and awaits Operator review in the
Wazuh dashboard. A pre-existing broad passwordless sudo rule discovered on the
pilot is a separate hardening blocker; it is not an accepted Wazuh dependency.

See the [A2 pilot contract](../soul/WAZUH_PASSIVE_AGENT_A2_BRIEF.md) and
[A2 review](../assessments/WAZUH_PASSIVE_AGENT_A2_REVIEW.md).

An Arch-family Operator workstation is a separate A2B lane. Wazuh does not
publish a native Arch package, so Soul does not install or automatically trust
an AUR package. If the Operator chooses a community package, review its exact
recipe, source checksums, install hook, configuration, service behavior, and
version relationship before enrollment. Permit manager TCP 1514 only from the
exact endpoint, remove temporary TCP 1515 access immediately after enrollment,
and keep endpoint-side Active Response disabled. See the
[A2B contract](../soul/WAZUH_ARCH_AGENT_A2B_BRIEF.md) and
[A2B review](../assessments/WAZUH_ARCH_AGENT_A2B_REVIEW.md).

## Selective ClamAV setup and use

Arch/CachyOS package setup:

```bash
sudo pacman -S --needed clamav
sudo freshclam
sudo systemctl enable --now clamav-freshclam-once.timer
```

Fedora package setup:

```bash
sudo dnf5 install clamav clamav-freshclam
sudo freshclam
sudo systemctl enable --now clamav-freshclam-once.timer
```

Do not enable `clamav-daemon`, `clamav-clamonacc`, or a ClamAV network socket.
After setup, verify and run a bounded scan:

```bash
make clamav-check
make verify-clamav-bounded-scan
make clamav-scan-downloads
```

The scan never removes or moves a finding. Review its owner-private receipt
under `Soul/private/security/clamav/scans/`. See the
[A3 contract](../soul/CLAMAV_SELECTIVE_SCAN_A3_BRIEF.md) and
[A3 review](../assessments/CLAMAV_SELECTIVE_SCAN_A3_REVIEW.md).

ClamAV placement follows ingress role, not fleet membership. Current defaults
qualify an Operator Downloads/import boundary and a backup guest's isolated
plaintext restore staging. Hypervisor VM storage, encrypted repositories, DNS
appliances, and maintenance-only laboratories are excluded unless their roles
later acquire an explicit plaintext ingress path.

## Current interaction boundary

Open the private Wazuh HTTPS URL and retrieve the administrator credential from
the Operator's password manager. A browser warning is expected for the initial
self-signed certificate. Do not copy credentials into Soul, Chat, project
state, or Git.

No Soul Chat security invocation exists. Do not paste Wazuh credentials or raw
alert payloads into Chat. A4a uses a separate read-only server-API identity;
A4b uses a separate read-only indexer identity. A4c may speak one generic static
high-priority cue while Voice Presence is idle, but it never speaks event
details or performs response work.

## Safe interpretation

A Wazuh alert is evidence requiring investigation, not proof that malware or an
intrusion occurred. A clean ClamAV scan is not proof that a file is safe. Soul
may summarize provenance and uncertainty, but the Operator remains the security
decision-maker.

An adapted workstation posture is likewise an interpretation, not a replacement
benchmark. A4d keeps Wazuh's raw score and counts visible, classifies every raw
failure exactly once, and never computes an adjusted compliance percentage. See
the [A4d contract](../soul/WAZUH_ADAPTED_POSTURE_A4D_BRIEF.md) and
[A4d review](../assessments/WAZUH_ADAPTED_POSTURE_A4D_REVIEW.md).
