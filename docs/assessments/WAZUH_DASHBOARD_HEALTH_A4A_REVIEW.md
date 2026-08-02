# Wazuh Dashboard Health A4a Review

Status: implementation candidate; deterministic local verification passed.
Live least-privilege credential enrollment and Operator visual acceptance remain
separate deployment gates.

## Implemented evidence

- `SoulCore::WazuhSecurityStatusService` validates an owner-private manifest,
  private HTTPS origins, exact mappings, CA path, and owner-only credentials.
- The service calls only authentication, API identity, manager status, and the
  bounded endpoint-agent inventory.
- Manager health, endpoint health, and per-device Wazuh association are
  normalized separately from Maintenance state.
- Alert evidence is explicitly reported as not integrated and no indexer or
  Active Response call exists.
- Status snapshots are written owner-only under
  `Soul/private/security/wazuh/status.json`; failure preserves the last known
  successful collection time.
- Administration now owns a dedicated Local Topology page using the same
  persisted fleet snapshot previously rendered under Guided Maintenance.
- Guided Maintenance cards expose separate security-health evidence and a safe
  HTTPS investigation link without changing their action authority.

## Verification

Run:

```bash
make verify-maintenance-local-topology
make verify-wazuh-security-status
```

The fixtures cover active, disconnected, and absent mapped agents; exclusion
of manager agent `000`; authentication failure; public DNS rejection; secret
absence; exact HTTP methods and paths; snapshot permissions; facade routing;
topology ownership; and isolated HTTPS links.

## Open review gates

- Create and inspect a dedicated whitelist-RBAC Wazuh API identity with only
  the A4a calls.
- Install ignored manifest/credential/CA files and collect one live snapshot.
- Confirm exact Soul device IDs against accepted Wazuh agent IDs.
- Review the Local Topology and maintenance-card presentation in the running
  Dashboard.
- Design A4b indexer alert access without silently widening the current
  loopback-only indexer boundary.
- Design A4c durable event cursor, deduplication, cooldown, privacy-safe voice
  phrases, and delivery that works when the Dashboard page is closed.
