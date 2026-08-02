# Wazuh Alert Evidence A4b Brief

## Objective

Project bounded recent Wazuh alert evidence into Soul without exposing the
indexer on the LAN, copying raw event payloads, or granting acknowledgement,
suppression, write, or remediation authority.

## Transport and identity

- The Wazuh Indexer remains bound to Vigil loopback only.
- A dedicated passphrase-less SSH key opens only
  `127.0.0.1:<reviewed local port> -> Vigil 127.0.0.1:9200`.
- The tunnel invokes OpenSSH with the Operator's owner-private SSH config
  explicitly selected, excluding system-wide client includes from this
  automation path.
- Its authorized-key entry has a forced inert command, no terminal, and one
  exact `permitopen` destination. It is not an administration identity.
- A separate internal indexer user maps to `soul_a4b_alert_reader`.
- The role has no cluster or tenant permissions and only
  `indices:data/read/search*` on `wazuh-alerts-*`.
- Indexer credentials live in an ignored owner-only file. The public CA copy is
  separate, and the indexer certificate is verified for `127.0.0.1`.

## Query and normalization

Soul issues one exact POST `_search` request with:

- fixed `wazuh-alerts-*` index pattern;
- timestamp and minimum-rule-level filters;
- explicit source fields only;
- a fixed maximum result count and response byte ceiling;
- no redirects, scripts, aggregations, updates, deletes, bulk operations, or
  caller-supplied query fragments.

Returned evidence contains a SHA-256 event identifier, timestamp, numeric level,
severity band, rule ID and bounded description, and agent ID/name. Raw event
IDs and unselected source fields are discarded. The owner-private cache marks
truncation honestly and preserves the last successful collection timestamp.

## Dashboard boundary

Guided Maintenance and Local Topology show aggregate recent alert evidence and
associate normalized alerts to existing exact agent mappings. Wazuh remains the
investigation console. Alert state never changes package, maintenance, reboot,
or device authority.

## Acceptance

- allowed alert search returns HTTP 200;
- monitoring-index search, cluster health, and security-role reads return 403;
- deterministic fixtures prove exact query fields and bounds, secret/raw-ID
  exclusion, owner-only persistence, safe failure, and read-only application
  operations;
- the deployed Dashboard presentation remains a separate human visual gate.
