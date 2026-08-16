# Fleet Observability A1.1 Review

Status: deployed, technically qualified, and Operator-approved on 2026-08-15.

## Candidate scope

A1.1 expands only the approved Grafana overview. It uses existing metric-only
Alloy evidence and adds no new endpoint software, listener, journal source,
alert, notification path, or operational authority.

## Files

- `config/fleet_observability_dashboard_a1_1.json`
- `deploy/observability/central/fleet-overview.json`
- `deploy/observability/central/render-dashboard.sh`
- `docs/soul/FLEET_OBSERVABILITY_A1_1_BRIEF.md`
- `docs/assessments/FLEET_OBSERVABILITY_A1_1_REVIEW.md`
- `scripts/verify-fleet-observability-a1-1.rb`

## Deterministic evidence

- [x] dashboard JSON parses and retains the approved UID
- [x] eight overview panels and five collapsed detail rows are present
- [x] every time-series panel uses stable portable role colors
- [x] all query families use existing reviewed Unix exporter metrics
- [x] the public dashboard contains placeholders rather than site coordinates
- [x] the renderer validates bounded owner-local region values
- [x] journal ingestion, alerts, and mutation remain absent
- [x] live Grafana deployment and query validation
- [x] Operator visual review of layout, map, labels, and row behavior

## Known limits

- Hardware temperatures and power are shown only where `hwmon` exports them.
  The later A2 refinement distinguishes CPU package, NVMe composite, and
  chipset evidence, rejects impossible readings, and places CPU busy beside
  package temperature. Package attention/critical thresholds are 85/95°C.
- Aggregate disk busy time can exceed 100 percent on multi-device hosts.
- Portable interface filtering cannot infer every future virtual interface.
- The region marker is deliberately approximate and owner-maintained.

## Live qualification evidence

All reviewed PromQL families returned successful live results from the existing
four-role pilot. This included zero-swap handling, normalized load, physical
disk throughput, aggregate busy time, request latency, filtered network
throughput and errors/drops, service restarts, uptime, OOM kills, available
temperature sensors, and honestly sparse power evidence. The owner-private map
query returned one city-level site marker and the current endpoint count.

The rendered dashboard was installed inside the Grafana guest, all owner-local
staging files were removed, Grafana restarted active, its database health was
`ok`, and its service journal contained no errors after provisioning.

## Human review checklist

- Confirm the map pin represents only the intended rough region.
- Confirm the overview remains readable without opening detail rows.
- Expand every row and check that labels, units, and legends are understandable.
- Confirm endpoint colors remain stable across overview and detail graphs.
- Confirm missing thermal or power evidence does not look healthy or zero.
- Confirm no panel suggests that visualization grants remediation authority.

The Operator completed this checklist against the live provisioned dashboard
and approved A1.1 on 2026-08-15.
