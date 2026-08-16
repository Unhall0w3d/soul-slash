# Fleet Observability A2/A3 Brief

Status: human-approved implementation brief. The Operator approved completing
the A2 operational dashboard and A3 Soul integration on 2026-08-16.

## Purpose

A2 extends the isolated Observatory deployment with operational evidence that
is useful during fleet maintenance and incident review. A3 gives Soul a
bounded, read-only projection of that evidence for the Dashboard, chat, voice,
and Incident Narrator.

## A2 operational evidence

The A2 dashboard may show:

- endpoint freshness and resource pressure;
- storage and host-network behavior already collected by Alloy;
- read-only switch and interface health through Prometheus SNMP Exporter;
- reboot markers derived from `node_boot_time_seconds`;
- maintenance lifecycle markers from a narrowly filtered journal source; and
- bounded Prometheus alerts rendered inside Grafana.

SNMP targets, addresses, credentials, auth profiles, and private device names
remain owner-local. SNMPv3 is preferred where the device supports it. The
committed Prometheus configuration accepts only a rendered file-discovery
document and a loopback-only exporter. It does not enable SNMP on a switch.

Journal collection is limited to the reviewed Soul maintenance and reboot
units. Alloy replaces the original message before transmission, retaining only
timestamp, endpoint identity, unit, priority, and a constant lifecycle marker.
The full system journal, command output, package output, paths, and credentials
must not be sent to Loki.

Alerts are dashboard-only. No Alertmanager, email, push notification,
acknowledgement mutation, automated maintenance, or remediation is introduced.
The exact initial rules cover stale endpoints, filesystem pressure, sustained
memory pressure, host-network errors, switch scrape failure, and switch port
errors. They explain evidence; they do not authorize action.

## A3 Soul projection

Soul may run one bounded foreground summary using an exact query registry. The
default transport uses the pre-existing reviewed owner SSH configuration and
SSH alias for Observatory and
loopback Prometheus. The transport accepts no user-supplied PromQL, shell
fragment, URL, credential, or host. It has a per-query timeout, a total query
limit, bounded result counts, and safe unavailable behavior.

The normalized result includes endpoint freshness, resource pressure, storage
and network exceptions, switch/interface health, firing alerts, boot evidence,
explicit gaps, and an optional owner-configured HTTPS Grafana drill-down URL.
It excludes raw metrics, arbitrary labels, addresses, credentials, command
lines, journal messages, and private filesystem paths.

The same projection is available through:

- `fleet_observability.summary` in the application contract;
- the Host Stewardship Dashboard;
- explicit fleet-observability questions in chat and voice; and
- Incident Narrator as one additional evidence source.

Chat and voice share the same routing path. Conversational wording must report
gaps honestly and offer the Grafana drill-down when configured. It must not
claim root cause or imply that a recommended action was performed.

## Lifecycle and authority

Every requested summary terminates `complete` or `failed`. It does not poll,
schedule, persist a private cache, or continue after returning. The already
approved Prometheus, Loki, Grafana, Caddy, Alloy, and SNMP exporter services are
the only persistent components in this slice.

Telemetry and the A3 projection have `mutation_authority: none`. They cannot
run maintenance, reboot a device, change an alert, change a switch, alter a
collector, or broaden an approval. Existing maintenance and destructive gates
remain unchanged.

## Acceptance

- deterministic A2 and A3 verifiers pass;
- public assets contain no owner-local identity, address, or credential;
- Prometheus rules validate and remain dashboard-only;
- journal filtering cannot forward original message content;
- switch data is honestly absent until owner-private SNMP configuration exists;
- A3 rejects arbitrary queries and bounds every returned collection;
- Dashboard, chat/voice, and Incident Narrator consume the same normalized
  summary; and
- live deployment and Operator visual/conversational review remain explicit
  review items rather than being inferred from tests.
