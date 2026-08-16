# Fleet Historical Telemetry and Observability A1 Review

Status: deployed, technically qualified, and Operator-approved on 2026-08-15.

## Candidate scope

A1 defines a dedicated unprivileged central guest, capped Prometheus and Loki
volumes, one TLS reverse proxy, authenticated ingest, a provisioned Grafana
surface, and a pinned Alloy metrics collector. It preserves Wazuh as the
security authority and keeps Soul read-only integration deferred.

## Files

- `config/fleet_observability_deployment_a1.json`
- `deploy/observability/central/*`
- `deploy/observability/collector/*`
- `docs/soul/FLEET_OBSERVABILITY_A1_BRIEF.md`
- `docs/assessments/FLEET_OBSERVABILITY_A1_REVIEW.md`
- `scripts/verify-fleet-observability-a1.rb`

## Required live evidence

- [x] exact unprivileged guest inventory and storage allocation
- [x] service-active and reboot-recovery evidence
- [x] loopback-only Prometheus and Loki listeners
- [x] authenticated HTTPS Grafana and ingest behavior
- [x] fresh metrics from each explicitly enrolled pilot endpoint
- [x] no Loki endpoint journal streams
- [x] current central and hypervisor resource headroom
- [x] Operator visual review of the provisioned Grafana dashboard

## Live qualification evidence

Qualification on 2026-08-15 confirmed the fixed unprivileged guest profile,
three dedicated volumes, autostart, and a clean post-reboot system state.
Prometheus, Loki, Grafana, and Caddy recovered automatically. Prometheus and
both Loki protocols listen on loopback; Caddy is the sole private-LAN listener
on HTTPS 443. SSH is disabled and masked after bootstrap, leaving the
hypervisor's container console as the administration path.

The subsequent Operator-approved full-management enrollment intentionally
replaced that bootstrap-only administration posture. SSH TCP 22 is now a
key-only management listener for one locked, non-root account whose sudo rule
permits only three digest-bound helper vectors. Caddy remains the sole
application-facing private-LAN listener; telemetry backend bindings are
unchanged.

Unauthenticated metrics and Loki ingest returned `401`; authenticated requests
reached each backend. Grafana rejected unauthenticated API access and accepted
the converged database-backed owner credential. Prometheus then reported fresh
stable identities for all four approved pilot roles. Loki returned no label
set because endpoint journal collection remains absent. The central guest had
more than 2.5 GiB available memory after warm-up, and both dedicated telemetry
volumes remained at one percent utilization.

Commands and checks included the two deterministic repository verifiers,
shell/Ruby syntax checks, `git diff --check`, service state, listener inventory,
authenticated HTTP probes, Prometheus queries, Loki label inspection, storage
inventory, and a full central guest reboot.

The Operator replaced the bootstrap Grafana administrator password with an
owner-chosen credential and verified the new login before saving it in the
password manager. Every temporary plaintext Grafana handoff file was then
removed from the guest; only the root-owned ingest enrollment credential
remains.

## Risk and authority

- Risk: persistent private-LAN infrastructure and endpoint collectors.
- Mutation: exact install/remove lifecycle only; no telemetry-driven mutation.
- Memory keys: none.
- Runtime lifecycle: installed services are persistent only because A1 requires
  and the Operator explicitly approves them.
- Known weakness: journal correlation remains absent until a privacy-safe
  selector design is separately accepted.
- The Operator approved the baseline layout, readability, endpoint identity,
  stable role colors, and operational usefulness before authorizing A1.1.
