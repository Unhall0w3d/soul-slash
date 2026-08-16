# Fleet Observability A1.1 Dashboard Brief

Status: candidate-complete dashboard refinement; live deployment and Operator
visual review remain explicit gates.

## Purpose

A1.1 turns the approved A1 metric baseline into a compact operational surface.
It changes only the provisioned Grafana dashboard and its reproducible render
path. The existing Prometheus, Loki, Grafana, Caddy, and Alloy topology remains
unchanged.

## Overview surface

The always-visible surface shows reporting endpoint count, sample freshness,
failed systemd units, maximum available temperature evidence, an approximate
global-presence marker, CPU busy percentage, memory used percentage, and root
filesystem use. Stable role colors remain identical across every time-series
panel.

## Collapsed evidence rows

Additional evidence is grouped into collapsed rows so the default dashboard
stays readable:

- compute and memory pressure: normalized load, swap use, and swap activity;
- storage behavior: throughput, aggregate device busy time, and request latency;
- network health: non-virtual-interface throughput, errors, and drops;
- services and stability: failed units, restart counts, uptime, and OOM kills;
- thermal and power sensors: maximum temperature and available power evidence.

Missing sensor families remain absent rather than being rendered as healthy.
Common virtual-interface and pseudo-device families are excluded from network
and disk aggregation. These portable filters may need later refinement for a
new platform, but they do not embed owner-local interface names.

## Location privacy

The committed dashboard contains only site placeholders. A root-owned `0600`
environment file supplies an Operator-selected city- or region-level label and
coordinates to `central/render-dashboard.sh`. The rendered dashboard exists
only inside the private Grafana guest. Precise home coordinates, private site
identity, and owner-local values must not enter Git.

## Boundaries

A1.1 adds no collector, journal source, alert rule, notification, automated
remediation, endpoint action, or Soul mutation authority. Grafana remains a
human exploration surface. The global map is descriptive and cannot initiate
an action.

## Acceptance

- every overview query returns useful or honestly absent live evidence;
- all five detail rows are collapsed by default and expand cleanly;
- endpoint role colors remain stable across every time-series panel;
- approximate location renders at the Operator-selected region;
- no private site value appears in the repository;
- Grafana remains healthy after dashboard replacement; and
- the Operator approves the live layout, labels, map, and readability.
