# Crucible Network-Device Syslog A0 Brief

```text
date: 2026-09-03
human_authorization: approved in active recovery conversation
implementation_authorized: yes
live deployment authorized: yes
risk: Class 3 persistent private-LAN receiver and security-event transport
```

## Objective

Use Crucible as the bounded retention point for syslog emitted by network
appliances that do not already have a native Alloy or Wazuh agent. Preserve
Vigil as the Wazuh authority, Observatory as the metrics and Loki authority,
and `/srv/soul-backup` as the encrypted Restic replica rather than combining
their storage or mutation boundaries.

The initial sender allowlist is limited to:

- Lattice (`192.168.124.10`);
- Loom (`192.168.124.11`); and
- the ASUSWRT-Merlin gateway (`192.168.124.1`) after its remote-log behavior is
  reviewed.

Linux hosts already covered by Alloy or Wazuh are excluded to avoid duplicate
collection. Additional appliances require a separate sender review.

## Verified host baseline

Crucible is a Fedora 44 Cloud Edition guest with SELinux enforcing and
firewalld active. Its root filesystem has 38 GiB free. The separately mounted
200 GiB XFS volume at `/srv/soul-backup` has 136 GiB free and remains dedicated
to backup data. The Wazuh agent is active. `rsyslog` and
`systemd-journal-remote` are not installed; `logrotate` is installed.

## Receiver boundary

- Install Fedora's official `rsyslog` package through DNF.
- Bind UDP/514 on Crucible's private interface. Do not expose TCP, TLS, or a
  public listener in A0.
- Add exact firewalld source rules for approved sender addresses only.
- Apply an rsyslog ruleset that accepts only the same exact sources and writes
  each source to a fixed file name. Unmatched packets stop without persistence.
- Use no dynamic hostname- or message-derived path.
- Use a bounded in-memory queue with no disk spool and no forwarding retry
  loop.
- Store files under `/var/log/network-devices`, not `/srv/soul-backup` and not
  inside either Restic repository.
- Create the directory root-owned `0750`; create log files `0640`.

## Retention and capacity

Rotate daily and when a file reaches 50 MiB, retain 14 rotations, compress old
files, and use `delaycompress`, `missingok`, and `notifempty`. This keeps the
first deployment deliberately small and aligns with Observatory's existing
14-day Loki horizon. Review measured volume before increasing retention.

The deployment must include a bounded size audit. If retained network logs
exceed 2 GiB in aggregate, the status check reports attention; it does not
delete outside logrotate or alter Restic retention.

## Wazuh integration

After local receipt and rotation are proven, add one explicit Wazuh
`localfile` input for `/var/log/network-devices/*.log` with syslog format.
Restart only `wazuh-agent`, verify its existing identity remains connected to
Vigil, and confirm a known test event reaches the authoritative Wazuh console.

Wazuh remains read-only from Soul. No Active Response, acknowledgement,
suppression, quarantine, automatic remediation, or raw-index backup is added.
The raw retained device files are not added to Soul or Operator Restic
manifests without a separate backup-policy review.

## Deployment order

1. Capture current package, firewall, SELinux, Wazuh, disk, and listener state.
2. Install and validate rsyslog without enabling the network listener.
3. Install the fixed-source ruleset and logrotate policy.
4. Add exact UDP/514 firewalld source rules.
5. Enable and start rsyslog; verify only the intended private socket exists.
6. Configure one switch sender and prove local receipt and rotation behavior.
7. Add the Wazuh localfile input and prove manager receipt without changing the
   agent identity or Active Response policy.
8. Add the remaining reviewed senders one at a time.
9. Produce a private deployment receipt and a human review artifact.

## Failure and rollback

- A package, syntax, SELinux, firewall, listener, disk, or Wazuh validation
  failure stops the gate before adding another sender.
- Disable the sender first, then close the exact firewall rules, stop and
  disable rsyslog, restore the prior Wazuh configuration, and restart only the
  Wazuh agent.
- Retained logs are quarantined for review rather than deleted automatically.
- Failure never modifies `/srv/soul-backup`, either Restic repository, Vigil,
  Observatory, or a device's unrelated management configuration.

## Explicit exclusions

- Internet exposure, wildcard firewall sources, SNMP trap ingestion, arbitrary
  relay, TCP/TLS syslog, or another dashboard.
- Linux host journal duplication, application logs already collected by Alloy
  or Wazuh, or telemetry-driven mutation.
- Storing live logs inside the Restic repository or granting the backup service
  access to the logging service.
- Persistent deployment before the Operator approves the exact candidate
  files, commands, rollback, and digest.

## Acceptance

1. Exact-source firewall and rsyslog filtering are independently verified.
2. One event from each approved sender reaches only its fixed file.
3. Rotation, compression, permissions, SELinux access, and the 2 GiB attention
   threshold are verified deterministically.
4. Crucible's Wazuh agent remains passive, connected, and identity-stable.
5. A known event is visible in Wazuh while secrets and raw logs remain absent
   from Soul responses and Git.
6. Disabling a sender or the receiver terminates collection without retry or
   background work beyond the explicitly approved services.
