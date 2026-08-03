# Wazuh Alert Evidence A4b Review

Status: accepted. Deterministic verification, live least-privilege
authorization, and authenticated Dashboard visual review pass.

## Live evidence

- Vigil's indexer remains reachable only on `127.0.0.1:9200`.
- Its certificate SAN contains only `127.0.0.1` and validates through the copied
  public root CA.
- The dedicated SSH key cannot execute a requested command and can open the
  single reviewed indexer tunnel.
- `soul_a4b_alert_reader` has no cluster or tenant permissions and only
  `indices:data/read/search*` on `wazuh-alerts-*`.
- Dedicated user `soul-dashboard-alerts` receives HTTP 200 for alert search and
  HTTP 403 for monitoring-index search, cluster health, and security-role reads.
- The accepted 24-hour level-7+ collection found 314 matches, returned the
  newest bounded 100, marked truncation, and reported one high and no critical
  alerts without returning raw event IDs or credentials.

## Verification

```bash
make verify-wazuh-alert-evidence
make verify-wazuh-security-status
make verify-maintenance-local-topology
```

## Human review outcome

- The Operator approved the alert summary and associated Atelier/Crucible card
  presentation in the authenticated deployed Dashboard on 2026-08-03.
