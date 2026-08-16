# Fleet Observability A2/A3 Review

Status: candidate-complete and partially live-qualified; Operator review is
required before acceptance.

## Candidate scope

A2 adds bounded operational evidence to the existing private Observatory:
dashboard-only alerts, reboot and redacted maintenance overlays, host network
and storage behavior, and owner-private SNMP switch/interface evidence. A3
projects the same evidence through one fixed, foreground, read-only summary for
Host Stewardship, explicit Chat/Voice questions, and Incident Narrator.

No arbitrary PromQL, raw journal line, notification route, acknowledgement,
maintenance action, reboot action, switch mutation, or telemetry-driven
remediation is introduced.

## Main files

- `config/fleet_observability_a2_a3.json`
- `deploy/observability/central/fleet-alerts.yml`
- `deploy/observability/central/fleet-operations.json`
- `deploy/observability/central/prometheus.yml`
- `deploy/observability/collector/config.alloy`
- `lib/soul_core/fleet_observability_summary_service.rb`
- `lib/soul_core/conversation_fleet_observability_service.rb`
- `docs/soul/FLEET_OBSERVABILITY_A2_A3_BRIEF.md`
- `scripts/verify-fleet-observability-a2.rb`
- `scripts/verify-fleet-observability-a3.rb`

## Deterministic evidence

- [x] A2 manifest preserves read-only, dashboard-only alert semantics
- [x] Prometheus rules and complete configuration pass `promtool`
- [x] SNMP Exporter is loopback-only and uses owner-private rendered inputs
- [x] journal collection is limited to exact reviewed units and replaces every
      original message before Loki transmission
- [x] A3 executes only nine fixed queries with per-query, total-time, result,
      and response-size bounds
- [x] A3 returns explicit gaps instead of manufacturing healthy zeros
- [x] Dashboard, Chat/Voice, and Incident Narrator consume the normalized A3
      summary without gaining mutation authority
- [x] public repository assets contain no private switch address, community,
      credential, or location
- [x] existing Host Stewardship and Incident Narrator verification remains green

## Live qualification evidence

- [x] Prometheus, Grafana, Loki, Caddy, and SNMP Exporter are active on the
      existing Observatory guest; backend/exporter listeners remain loopback-only
- [x] six bounded alert rules are loaded
- [x] the A2 operations dashboard is provisioned
- [x] the fleet overview now separates CPU package, NVMe composite, and chipset
      temperature, rejects impossible sensor values, and places CPU busy beside
      package temperature with reviewed 85/95°C thresholds
- [x] all four enrolled Linux roles remain fresh in the central metric lane
- [x] one reviewed switch reports successfully through the owner-private config
- [x] A3 returns a complete response with four reporting endpoints, no stale
      endpoint, and no host network error
- [ ] the second reviewed switch is reachable from the Operator host but not
      from Observatory; A3 reports it unavailable and raises the reviewed alert
- [x] the workstation and backup-target roles received the exact A2 Alloy journal-filter upgrade
      in a supervised password-owning session; both services are active and the
      Alloy identities hold only their reviewed journal-read group addition

## Known limits

- The unavailable switch likely restricts its SNMP manager source. Correcting that requires an
  exact reviewed switch configuration change; this candidate does not guess or
  weaken the switch ACL.
- The host system OpenSSH configuration tree has an unrelated unsafe ownership
  defect. A3 deliberately selects the reviewed owner SSH configuration instead
  of bypassing OpenSSH checks. The host defect remains separately repairable.
- Maintenance overlays remain sparse until reviewed maintenance units emit new
  lifecycle evidence; all four enrolled collectors now have the exact filter.
- Alerts remain visible only in Grafana and the read-only A3 projection.

## Human review checklist

- Open the Fleet Operations dashboard and inspect alert, resource, network,
  reboot, switch, and maintenance panels.
- Confirm gaps and unavailable sources do not resemble healthy evidence.
- Expand **Administration → Host Stewardship → Observatory**, run one manual
  refresh, and use the HTTPS Grafana drill-down.
- Ask in Chat and Voice: `How does fleet observability look?` Confirm both paths
  report the same endpoint, network, alert, and gap state without proposing or
  performing an action.
- Compose an Incident Narrative and confirm Observatory evidence is
  source-attributed, cautious, and does not claim root cause.
- Confirm the switch gap remains visible as incomplete rather than being treated
  as an acceptance failure or hidden.

## Commands

```bash
make verify-fleet-observability-a2
make verify-fleet-observability-a3
make verify-incident-narrator
make verify-host-stewardship-file-steward
node --check assets/dashboard/dashboard.js
git diff --check
```

Machine qualification makes this candidate ready for review. It does not make
the live visual, Chat, Voice, or Incident Narrator experience Operator-approved.
