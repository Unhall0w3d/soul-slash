# Wazuh Dashboard Health A4a Brief

## Objective

Project bounded Wazuh manager and endpoint-agent health into Soul's existing
Administration surfaces without embedding Wazuh, querying its indexer, or
granting remediation authority.

## User surfaces

- Move Operations Topology from Guided Maintenance to **Administration → Local
  Topology**. The new page reuses the persisted fleet-status contract and has
  no independent discovery or mutation authority.
- Show one separate Wazuh health block on an associated maintenance device
  card. Operational maintenance state and security-monitoring state must never
  overwrite one another.
- Show a compact Wazuh monitoring-plane summary on Guided Maintenance and Local
  Topology.
- Open the authoritative Wazuh console through a reviewed HTTPS link in a new
  browser context. Do not iframe or reproduce the investigation console.

## Private configuration

`SOUL_WAZUH_INTEGRATION_FILE` selects one owner-private JSON manifest with
schema `soul.wazuh.integration.v1`. It contains only:

- reviewed private HTTPS origins for the server API and dashboard;
- absolute paths to a trusted CA certificate and separate credential file;
- exact Soul `device_id` to Wazuh `agent_id` mappings.

The manifest must not contain credentials. The credential file is owner-only
JSON containing a dedicated Wazuh API username and password. Neither file is
tracked. Mapping is explicit; hostname similarity never creates an
association.

## Read-only API contract

A4a may call only:

- `POST /security/user/authenticate?raw=true`;
- `GET /`;
- `GET /manager/status`;
- `GET /agents` with a fixed field selection and bounded limit.

All origins must use HTTPS, resolve only to private IPv4 addresses, and use the
reviewed ports. Connections are pinned to the already validated private address
while retaining the configured hostname for TLS verification. Redirects, oversized
responses, malformed structures, public resolution, and authorization failure
degrade to an unavailable snapshot. Returned state is allowlisted and cannot
contain the password or bearer token.

The dedicated Wazuh API role should use whitelist RBAC and grant only the
minimum permissions needed by those calls. The administrator identity is not
an accepted runtime credential.

## Deliberate exclusions

- Wazuh indexer or alert queries;
- alert counts, vulnerability findings, or ClamAV detections;
- Active Response, acknowledgement, suppression, quarantine, or remediation;
- background polling or spoken security notifications;
- firewall changes or expanded indexer exposure.

These are not implied by successful agent-health collection. Alert access is a
separate A4b gate because the authoritative alert records live in the Wazuh
indexer, which remains loopback-only. Durable deduplicated cues and optional
Voice Presence delivery are a later A4c gate after alert access is qualified.

## Acceptance

- deterministic fixtures prove exact endpoint calls, response bounds, private
  resolution, explicit mappings, TLS inputs, secret exclusion, and safe failure;
- persisted status is owner-only and preserves the last successful timestamp;
- the application contract exposes read-only live and snapshot operations;
- topology is absent from Guided Maintenance and available under Local
  Topology using the same status snapshot;
- card actions remain maintenance/reboot only and Wazuh links grant no mutation;
- the Wazuh console remains the authoritative investigation surface.
