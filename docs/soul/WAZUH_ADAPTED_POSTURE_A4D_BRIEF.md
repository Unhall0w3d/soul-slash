# Wazuh Adapted Posture A4d Brief

## Objective

Present an owner-reviewed Atelier interpretation of Wazuh SCA findings beside,
never instead of, the raw Wazuh result. The layer explains why an Arch/CachyOS
workstation may intentionally differ from a generic benchmark without changing
the benchmark, suppressing findings, or claiming a replacement score.

## Authority boundary

- Wazuh remains the authoritative source of the raw policy, scan, score, and
  pass/fail/not-applicable counts.
- A4d reads one ignored owner-private JSON manifest selected by
  `SOUL_WAZUH_POSTURE_FILE`.
- A4d performs no Wazuh API/indexer query, SSH command, acknowledgement,
  suppression, remediation, or score calculation.
- The manifest must be a regular non-symlink owner-private file and is bounded
  to 256 KiB.
- Every raw failed check ID must appear exactly once in the adapted review.
  Missing, duplicate, unsupported, or extra classifications fail closed.
- The source scan ID and SHA-256 policy-state hash bind the review to one exact
  Wazuh scan rather than a moving score.

The source template is
`config/wazuh-compliance-posture.example.json`. Deployment-specific scan IDs,
host policy decisions, and internal context stay under ignored
`Soul/private/security/wazuh/`.

## Classification contract

The manifest uses four explicit, non-overlapping classifications:

1. `verified_effective_control` — independent host evidence showed an
   equivalent or stricter control while the policy parser still reported fail.
2. `accepted_workstation_exception` — the owner intentionally retained a
   workstation capability or system design that conflicts with the benchmark.
3. `policy_or_parser_limitation` — the policy is obsolete, duplicated,
   internally inconsistent, or not meaningful on this platform.
4. `genuine_remaining_decision` — a real hardening choice remains open. These
   findings keep the adapted posture in attention state.

This is not an adjusted compliance percentage. Soul shows the unaltered raw
score and counts, the review version and timestamp, the classified failure
count, and the four classification counts and summaries.

## Dashboard behavior

Guided Maintenance and Local Topology append the raw CIS score and adapted
review summary to their existing Wazuh monitoring plane. The associated device
card exposes a collapsed detail block with the exact raw counts and category
summaries. Existing HTTPS investigation links still open Wazuh, and no new
mutation control is introduced.

## Verification

```bash
make verify-wazuh-compliance-posture
make verify-wazuh-security-status
make verify-wazuh-alert-evidence
make verify-maintenance-local-topology
```
