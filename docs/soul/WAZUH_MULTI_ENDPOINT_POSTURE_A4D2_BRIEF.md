# Wazuh Multi-Endpoint Posture A4d2 Brief

## Objective

Extend the accepted A4d interpretation layer from one Atelier review to a
bounded set of independently scan-bound endpoint reviews. Guided Maintenance,
Local Topology, Chat, and Voice must show the review associated with the exact
Wazuh agent without replacing or recalculating any raw Wazuh result.

## Authority boundary

- Wazuh remains authoritative for every raw policy, scan, score, and count.
- A4d2 reads one ignored owner-private JSON manifest selected by the existing
  `SOUL_WAZUH_POSTURE_FILE` setting.
- The manifest contains at most 16 endpoint entries with unique non-manager
  agent IDs. Each entry retains the A4d exact scan ID/hash binding and complete,
  unique classification requirement.
- A4d2 performs no Wazuh API/indexer query, SSH command, acknowledgement,
  suppression, remediation, score calculation, or remote mutation.
- Version-one manifests remain readable as a one-entry compatibility input;
  new multi-endpoint manifests use `soul.wazuh.compliance-postures.v2`.
- The existing `accepted_workstation_exception` key remains stable for stored
  data compatibility. In A4d2 it means an owner-accepted endpoint-specific
  design exception, including server availability and recovery requirements.

## Projection contract

- Service output contains a bounded `postures` array and aggregate summary.
- Each posture retains its raw result, adapted review, verification flags, and
  per-agent state.
- Overall state is `attention` when any entry has a genuine remaining decision.
- Dashboard device cards select only the posture whose `agent_id` matches the
  device-to-agent association.
- Chat and Voice report bounded aggregate counts rather than implying one raw
  score describes the entire fleet.

## Crucible review boundary

The initial Crucible entry binds to post-reboot Wazuh scan `910600637` (raw
69%; 129 pass, 56 fail, 5 not applicable) and records independent
effective-state evidence beside that unchanged result. Accepted exceptions
preserve recovery, backup, Fedora/systemd-native, IPv6, and bounded-retention
behavior where blind benchmark conformance would add availability risk.

## Verification

```bash
make verify-wazuh-compliance-posture
make verify-wazuh-conversation-status
make verify-wazuh-security-status
make verify-wazuh-alert-evidence
make verify-maintenance-local-topology
```
