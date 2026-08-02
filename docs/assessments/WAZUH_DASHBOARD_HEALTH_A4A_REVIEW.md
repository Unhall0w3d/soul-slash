# Wazuh Dashboard Health A4a Review

Status: live least-privilege enrollment, collection, and Operator visual
acceptance completed; deterministic verification passed.

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
- Vigil presents a private CA-signed API certificate valid for
  `vigil.herz.soul` and its reviewed private address; Soul trusts only the
  installed public CA copy.
- Dedicated API user `soul-dashboard` has one custom role containing exactly
  `agent:read` on `agent:id:*` and `manager:read` on the manager resource. It no
  longer carries Wazuh's broader built-in `readonly` role.
- Live authorization verifies the manager-status and bounded agent-inventory
  requests while a broader rules read is denied with HTTP 403.
- Exact live mappings associate Atelier with agent `002` and Crucible with agent
  `001`; both agents and all ten required manager daemons were active on the
  accepted 2026-08-02 collection.
- Expected stopped optional daemons no longer create a false manager warning,
  and the ascending agent sort is percent-encoded for Wazuh 4.14 query parsing.
- The deployed Dashboard was restarted onto the accepted revision and reviewed
  in its normal authenticated surface. Guided Maintenance reports a healthy
  two-of-two endpoint summary; Atelier and Crucible show their exact active
  agent associations separately from maintenance state; Local Topology shows
  the same read-only monitoring plane; and a manual security refresh completed
  without an application error or remediation authority.

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

- Design A4b indexer alert access without silently widening the current
  loopback-only indexer boundary.
- Design A4c durable event cursor, deduplication, cooldown, privacy-safe voice
  phrases, and delivery that works when the Dashboard page is closed.
