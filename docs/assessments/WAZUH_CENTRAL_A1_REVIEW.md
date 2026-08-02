# Wazuh Central A1 Review

## Status

Live central deployment is candidate-complete and blocked for Operator visual
review. No endpoint agent or ClamAV component was installed.

## What was implemented

- One dedicated Ubuntu 24.04 Wazuh central VM with fixed 4 vCPU, 8 GiB RAM,
  60 GiB storage, boot persistence, guest agent, and deletion protection.
- Wazuh manager, indexer, dashboard, and Filebeat from the official 4.14
  channel, with exact matched installed versions.
- Private-LAN dashboard access, workstation-only SSH/API access, blocked agent
  ports, and loopback-only indexer access.
- Vendor package repository disabled after installation.
- One 30-day ISM policy attached to current and future alert, monitoring, and
  statistics indices.
- A private DNS record and pinned key-only SSH identity in owner-local state.
- One ignored, credential-free live receipt beneath
  `Soul/private/security/wazuh/`.

Deployment-specific names, addresses, keys, host fingerprints, boot identities,
and credentials remain outside tracked source.

## Tracked files changed

- `docs/soul/WAZUH_CENTRAL_A1_BRIEF.md`
- `docs/assessments/WAZUH_CENTRAL_A1_REVIEW.md`
- `docs/guides/SECURITY_MONITORING.md`
- `README.md`
- `docs/ROADMAP.md`
- `config/project_tracker_seed.json`

## Validation performed

- official Ubuntu SHA-256 manifest matched the imported image;
- cloud-init completed successfully;
- base guest and post-Wazuh reboot identities changed as expected;
- guest agent and all four central services became active;
- all three Wazuh packages report one exact version;
- dashboard returns an HTTPS redirect from the private LAN;
- unauthenticated server/indexer API requests return 401;
- indexer is loopback-bound and LAN-unreachable;
- ports 1514 and 1515 are LAN-unreachable;
- firewall rules persist after reboot;
- Wazuh repository has no enabled `deb` line;
- current alert and monitoring indices accepted the 30-day policy;
- no failed systemd unit exists;
- tracked Project Timeline JSON and documentation checks pass.

## Known weaknesses

- The generated dashboard certificate is self-signed and requires a private-LAN
  browser exception until later TLS hardening.
- The Operator has not yet visually reviewed the Wazuh dashboard.
- No agent data exists, so alert volume, vulnerability accuracy, resource cost,
  and false positives are still unknown.
- Agent ports intentionally remain closed.
- Raw Wazuh local-log retention and central backup are not yet qualified.
- The installer channel resolved a newer patch than the documentation release
  index; exact installed component matching was verified, but future upgrades
  remain disabled and separately reviewed.

## Local-model evaluation

None. Model output cannot approve persistent security infrastructure or its
privileges.

## Memory keys added or used

None.

## Lifecycle states touched

`complete` for bounded provisioning and verification steps;
`blocked_for_human_review` for the A1 rollout as a whole.

## Risk classification

Persistent privileged security infrastructure on a private VM. It is isolated
from existing fleet mutation paths, has a narrow firewall, and has no endpoint
or remediation authority in A1.

## Human review checklist

- [ ] Log in to the private Wazuh dashboard.
- [ ] Confirm the central overview loads without component errors.
- [ ] Inspect server and indexer health.
- [ ] Confirm zero endpoint agents is expected at A1.
- [ ] Accept the temporary self-signed certificate behavior.
- [ ] Approve A2 opening ports 1514/1515 for one passive pilot agent.
