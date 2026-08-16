# Fleet Observability deployment assets

These files implement the public, reusable portion of Fleet Observability A1.
They contain no hostnames, addresses, credentials, certificates, or private
fleet identities.

`central/` is installed only inside the dedicated unprivileged central guest.
`collector/` is installed only on explicitly enrolled Linux endpoints. Both
installers require a root-owned `0600` environment file created outside the
repository. See each directory's example file for the required fields.

The assets do not create a Proxmox guest, choose an address, modify DNS, enroll
an endpoint, or remove an existing deployment. Those are owner-local operations
bound to the A1 brief and separate live evidence.

The A1.1 dashboard adds an approximate global-presence marker. Its site label
and coordinates are supplied through the root-owned central environment file
and rendered by `central/render-dashboard.sh`; only placeholders exist in Git.
Use city- or region-level coordinates rather than a precise home location.

The central installer avoids package recommendations, binds Prometheus,
Grafana, and both Loki protocols to loopback, disables Caddy's port-80 redirect,
and converges Grafana's database-backed administrator credential. The collector
installer validates a pinned Alloy binary before enabling its loopback-only
service. A2 replaces the former metric-only journal boundary with one exact
maintenance-unit projection: original messages are replaced before they leave
the endpoint. A2 also provisions a second operations dashboard,
dashboard-only Prometheus alert rules, and a loopback SNMP exporter. Switch
targets and SNMP authentication are owner-private inputs and remain absent by
default. Existing deployments use `central/upgrade-central-a2.sh` and
`collector/upgrade-collector-a2.sh`, preserving saved Grafana and ingest
credentials instead of rerunning bootstrap.

For the accepted owner deployment, `scripts/render-fleet-observability-snmp-config`
can combine the pinned upstream exporter configuration with the existing
owner-private indexed switch values. Slots 1 through 8 use
`SOUL_OBSERVABILITY_SWITCH_N_ID`, `_ADDRESS`, and `_SNMP_COMMUNITY`; partial
slots fail closed. The renderer emits mode-`0600` files outside Git and never
prints a community. The central A2 upgrade accepts those two rendered files as
optional exact inputs.

After the Operator saves the initial Grafana credential, run the reviewed
`central/finalize-credential-handoff.sh` inside the central guest. It removes
the plaintext Grafana bootstrap value and retains only the mode-`0600` ingest
credential needed for deliberate future collector enrollment.
