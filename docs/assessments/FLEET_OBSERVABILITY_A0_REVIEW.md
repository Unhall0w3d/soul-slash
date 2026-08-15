# Fleet Historical Telemetry and Observability A0 — Human Review

Status: candidate-complete; human architecture review remains pending.

## Candidate decision

A0 selects Grafana Alloy, Prometheus, Loki, and Grafana as a small-fleet
operational observability plane. Wazuh remains the security authority. Soul's
future participation is a bounded read-only summary, not raw telemetry storage,
open-ended query generation, or remediation.

## Files changed

- `config/fleet_observability_architecture_a0.json`
- `docs/soul/FLEET_OBSERVABILITY_A0_BRIEF.md`
- `docs/assessments/FLEET_OBSERVABILITY_A0_REVIEW.md`
- `scripts/verify-fleet-observability-a0.rb`
- `Makefile`
- `docs/CURRENT_STATE.md`

The owner-private Project Timeline was updated locally and remains excluded
from the public repository.

## Research basis

The referenced `ucs_traffic_monitor` project demonstrates the durable pattern
of a read-only collector, historical time-series storage, and Grafana views for
utilization, errors, congestion, and correlation. Its documented deployment
uses Telegraf's exec input, a Python collector, InfluxDB, Grafana, and a
CentOS 7-era host. A0 retains the separation and dashboard concepts, not that
exact implementation.

Current Grafana Alloy documentation supports an embedded Unix exporter and a
journald source. Prometheus documents local single-node time-series storage
with time and size retention; Loki documents bounded retention through its
compactor. Those capabilities support the smaller selected component set.

## Deterministic evidence

```text
make verify-fleet-observability        PASS
ruby -c scripts/verify-fleet-observability-a0.rb PASS
ruby JSON parse architecture manifest PASS
git diff --check                       PASS
```

The verifier checks the exact stack, pilot roles, retention values, stable
labels, privacy exclusions, Wazuh separation, future Soul boundary, deferred
persistence, and absence of new deployment artifacts.

## Local environment evidence

At candidate time, the Operator workstation had Docker available but did not
have Grafana, Prometheus, node_exporter, Loki, Alloy, Telegraf, or InfluxDB
installed as native packages. A0 did not install or start any of them.

## Local LLM evaluation

None. Component selection, retention, privacy, and authority are architecture
decisions. A language-model evaluation cannot approve them.

## Memory, lifecycle, and risk

- Memory keys added or used: none.
- Runtime lifecycle states touched: none.
- Mutation authority: none.
- Risk classification: architecture-only candidate for a future persistent
  private-LAN observability system.

## Known weaknesses

- Exact guest placement and resources still require live hypervisor capacity
  evidence.
- The Prometheus/Loki single-node design trades high availability for lower
  operational complexity.
- Journal selectors and size caps are requirements, not deployed proof.
- No dashboard proves the chosen signals are yet useful.
- No Soul summary adapter, alert policy, or retention enforcement exists.

## Human review checklist

- [ ] Alloy is acceptable as the common Linux endpoint collector.
- [ ] Prometheus and Loki are acceptable initial single-node stores.
- [ ] Grafana is the correct human drill-down surface.
- [ ] Wazuh and operational telemetry remain clearly separated.
- [ ] The four-role pilot and second-wave deferrals are appropriate.
- [ ] Thirty-day metrics and fourteen-day operational logs are appropriate.
- [ ] The log exclusions and stable-label policy protect private content.
- [ ] Raw telemetry may remain outside Restic/DRS backups by default.
- [ ] A dedicated private-LAN guest is preferable to co-location.
- [ ] Approve, revise, or reject drafting the A1 deployment brief.
