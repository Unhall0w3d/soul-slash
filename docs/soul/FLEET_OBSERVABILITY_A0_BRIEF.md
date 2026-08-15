# Fleet Historical Telemetry and Observability A0 Brief

Status: human-approved for architecture candidate implementation on 2026-08-15.

## Purpose

Adapt the useful architecture lessons from `ucs_traffic_monitor` to Soul's small
Linux fleet without copying that project, adopting its aging CentOS-era
deployment, or turning Soul into a second security-information system.

The useful pattern is separation of concerns: endpoint collection, historical
storage, human visualization, and a narrow read-only assistant projection. A0
selects a modern version of that pattern and records its privacy, retention,
identity, and authority boundaries before any persistent component is installed.

## Selected architecture

- **Grafana Alloy** on explicitly enrolled Linux endpoints. Its embedded Unix
  exporter supplies bounded host metrics and its journal source can forward a
  narrow allowlist of operational records.
- **Prometheus** as the initial single-node metrics store.
- **Loki** in single-binary mode for a narrow operational-log lane.
- **Grafana** as the authoritative human exploration surface for operational
  telemetry.
- **Wazuh** remains the authoritative security investigation surface. Grafana
  and Loki do not duplicate or reinterpret its raw security corpus.
- **Soul** eventually receives one bounded foreground read-only projection of
  normalized metrics and operational signals. It does not retain raw query
  results or mutate the observability stack.

Telegraf and InfluxDB remain valid tools, but they are not selected for the
pilot. Alloy reduces endpoint component count by combining host metric export
and narrowly filtered journal forwarding, while Prometheus and Loki align with
Grafana's native operational model.

## Deployment boundary

The central stack belongs in one dedicated unprivileged Linux guest on the
private LAN, selected through owner-private configuration. It must not be
co-located with DNS, the Wazuh manager, or the Soul Dashboard merely for
convenience. Exact placement, guest identity, resources, storage, local DNS,
certificates, firewall rules, and rollback require an A1 deployment brief and
current capacity evidence.

A0 creates no guest, container, package, image, volume, listener, account,
service, unit, timer, schedule, firewall rule, or endpoint agent. Docker being
available on the workstation is not deployment approval.

## Pilot scope

The first wave is limited to the Operator workstation, primary hypervisor,
secondary hypervisor, and backup target. DNS/resolver infrastructure, the
passive security sensor, and selected Linux guests are a second wave.
Status-only consumer devices, phones, switches, televisions, speakers, and
mobile devices are outside the A0/A1 pilot. SNMP and Proxmox API metrics are
separate extensions, not implied by endpoint metrics.

## Metrics and operational logs

The metrics allowlist covers CPU/load, memory/swap, filesystem capacity and
inodes, disk I/O, network bytes/errors/drops, available hardware temperatures,
failed-systemd-unit count, uptime, and boot identity.

The log allowlist covers selected service lifecycle records, kernel hardware
and link events, and bounded maintenance-service events. It explicitly omits:

- authentication and authorization logs;
- raw Wazuh security events;
- command lines and shell history;
- application message bodies;
- Soul chats, memory, artifacts, and creative-project content; and
- credentials, tokens, and environment values.

Endpoint selection and journal match expressions must be exact configuration,
not an open-ended all-logs default.

## Identity and cardinality

Telemetry uses stable, low-cardinality Soul identities: `device_id`, `role`,
`platform`, and `environment`. DHCP addresses, MAC addresses, filesystem paths,
user names, process command lines, and arbitrary journal fields cannot become
long-lived labels.

## Retention and backup

- Metrics retain 30 days.
- Operational logs retain 14 days.
- Both stores require a dedicated local volume and an explicit size limit
  before deployment; Prometheus may consume at most 80 percent of its assigned
  metrics volume.
- Raw telemetry is excluded from Soul's Restic/DRS backup scope by default.
  Provisioned dashboards, reviewed collector configuration, and recording or
  alert rules are backed up as configuration.

The pilot treats telemetry history as reconstructible operational evidence,
not irreplaceable owner data. Longer retention or raw-data backup requires a
separate capacity and recovery decision.

## Operator views

The first Grafana provision supplies fleet overview, host resource detail,
network and storage health, maintenance/reboot correlation, and operational-log
exploration. Dashboards must show unavailable and stale data honestly.

## Future Soul contract

The proposed future operation is `observability.fleet.summary`. It will run in
the foreground, issue only fixed reviewed read-only queries, normalize bounded
results, report freshness and gaps, and terminate as `complete` or `failed`
with `mutation: none`. Incident Narrator may consume that normalized projection
only; it must not query Prometheus or Loki directly or present temporal
correlation as root cause. That operation is not implemented by A0.

## Acceptance

- the machine-readable architecture agrees with this brief;
- every selected component has one clear responsibility;
- Wazuh remains authoritative for security;
- endpoint identity is stable and label cardinality is bounded;
- metrics, logs, retention, backup, and pilot roles are explicit;
- raw private content and security events are excluded;
- persistent deployment and automatic collection are visibly unauthorized;
- no deployment artifact or runtime dependency is added by A0; and
- the Operator approves or revises the architecture before A1 is drafted.

## Explicitly deferred

Central guest creation, packages or containers, listeners, firewall changes,
Alloy enrollment, automatic collection, alerts, notifications, Soul and
Incident Narrator adapters, Proxmox API metrics, SNMP, and long-term telemetry
backup are deferred.

## Primary references

- [ucs_traffic_monitor](https://github.com/paregupt/ucs_traffic_monitor)
- [Grafana Alloy Unix exporter](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.unix/)
- [Grafana Alloy journald source](https://grafana.com/docs/alloy/latest/reference/components/loki/loki.source.journal/)
- [Prometheus storage](https://prometheus.io/docs/prometheus/latest/storage/)
- [Loki retention](https://grafana.com/docs/loki/latest/operations/storage/retention/)
