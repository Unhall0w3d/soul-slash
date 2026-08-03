# Wazuh Adapted Posture A4d Review

## Result

Implementation candidate ready for Operator review. A4d adds a distinct
read-only posture service and dashboard projection while preserving the raw
Wazuh result unchanged.

## Reviewed properties

- `SoulCore::WazuhCompliancePostureService` validates one owner-private,
  versioned manifest and returns no credentials or private paths.
- Raw Wazuh score and pass/fail/not-applicable counts are explicit and marked
  unaltered; the service does not calculate an alternate score.
- All raw failures must be classified exactly once across the four bounded
  categories.
- An open decision produces `attention`; accepted exceptions and parser notes
  do not masquerade as Wazuh passes.
- The application contract exposes only `status` and `snapshot` read paths.
- The dashboard renders the adapted explanation on the exact agent-associated
  device card and leaves Wazuh as the investigation surface.
- Existing A4a health, A4b alert, A4c notification, and maintenance mutation
  boundaries remain unchanged.

## Deployment evidence still required

- install the reviewed Atelier manifest under ignored owner-private state;
- select it with `SOUL_WAZUH_POSTURE_FILE`;
- restart the user dashboard service;
- confirm the raw 45% result, 59 pass / 71 fail / 7 N/A counts, four adapted
  category counts, and Wazuh investigation link in the browser.

## Verification

```bash
make verify-wazuh-compliance-posture
make verify-wazuh-security-status
make verify-wazuh-alert-evidence
make verify-wazuh-alert-notifications
make verify-maintenance-local-topology
```
