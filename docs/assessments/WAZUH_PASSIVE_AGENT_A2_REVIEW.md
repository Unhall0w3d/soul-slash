# Wazuh Passive Agent A2 Review

## Status

The single Fedora pilot is machine-qualified and blocked for Operator review in
the Wazuh dashboard. Cohort expansion, ClamAV, and response authority remain
unapproved.

## What was implemented

- One supported Fedora 44 x86-64 endpoint enrolled against the accepted Wazuh
  central platform.
- Exact Wazuh agent `4.14.7-1`, matching the central release and carrying the
  official package signature.
- Persistent agent service with the vendor repository disabled after install.
- Enrollment port opened only for key acquisition and then removed.
- Encrypted event transport restricted to the exact pilot endpoint.
- Endpoint Active Response explicitly disabled; the manager contains vendor
  command definitions but no active-response assignment.
- One ignored, credential-free owner-local receipt under
  `Soul/private/security/wazuh/`.

No ClamAV package, scan, quarantine, response, or Soul integration was added.

## Files changed

- `docs/soul/WAZUH_PASSIVE_AGENT_A2_BRIEF.md`
- `docs/assessments/WAZUH_PASSIVE_AGENT_A2_REVIEW.md`
- `docs/assessments/WAZUH_CENTRAL_A1_REVIEW.md`
- `docs/guides/SECURITY_MONITORING.md`
- `docs/ROADMAP.md`
- `config/project_tracker_seed.json`

## Deterministic validation

- Fedora release and kernel identified successfully.
- Package signature reports RSA/SHA-256 with the expected vendor signing key.
- Installed agent version matches central version `4.14.7`.
- Package repository reports `enabled=0`.
- Agent configuration validation succeeds.
- Service reports both `enabled` and `active`.
- Manager reports the pilot `Active` after an agent service restart.
- Initial file-integrity scan starts and completes.
- Endpoint has an established TCP event connection to the central manager.
- Registration port was removed after enrollment; only endpoint-scoped event
  transport remains.
- Endpoint Active Response reports `disabled=yes`; manager configuration has no
  active-response assignment.
- No failed systemd unit or agent ERROR/CRITICAL log entry was observed.
- Initial agent installation occupies approximately 29 MiB on disk.
- Five principal agent processes used approximately 66 MiB resident memory in
  aggregate during the initial collection window. File-integrity startup work
  was bounded but still settling when the receipt was recorded.

## Known weaknesses and blockers

- Operator review of the new endpoint, inventory, vulnerability evidence, and
  alert volume in the Wazuh dashboard remains open.
- Settled resource use and false-positive volume require observation through
  normal use; one startup sample cannot establish a long-term baseline.
- The pilot endpoint contains a pre-existing cloud-init sudo rule granting its
  administration user unrestricted passwordless root. This contradicts the
  intended digest-bound maintenance authority and blocks broader agent rollout
  until a separately reviewed hardening change removes the broad grant without
  breaking accepted maintenance operations.
- The agent installer could not run through the QEMU guest-agent execution
  path because SELinux correctly prevented the guest-agent domain from
  executing the package manager. SELinux was not disabled or bypassed; the
  approved owner SSH path was used instead.
- A genuine endpoint reboot-persistence test remains available but is not
  required for this review; service restart/reconnect is proven and repeated
  VM reboots are avoided without a clear need.

## Local-model evaluation

None. Model output cannot approve security policy, endpoint privilege, or
persistent agent infrastructure.

## Memory keys added or used

None.

## Lifecycle states touched

`complete` for bounded installation, enrollment, passive-policy enforcement,
and verification; `blocked_for_human_review` for A2 as a whole.

## Risk classification

Persistent passive security telemetry agent on one private Linux endpoint.
Response authority is explicitly disabled at the endpoint and unassigned at
the manager. A separate high-priority endpoint sudo-policy defect was detected
and retained rather than silently modified.

## Human review checklist

- [ ] Open the Wazuh dashboard and select the single enrolled pilot endpoint.
- [ ] Confirm it is Active and the displayed OS/kernel identity is credible.
- [ ] Review inventory, vulnerability, file-integrity, and configuration data.
- [ ] Review initial alerts for usefulness and unacceptable noise.
- [ ] Confirm no response or remediation control is expected at A2.
- [ ] Approve or reject the measured passive resource cost.
- [ ] Approve a separate exact repair for the broad passwordless sudo rule.
- [ ] Decide whether to expand to one additional endpoint or proceed first to
  the bounded ClamAV A3 pilot.
