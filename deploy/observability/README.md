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
service. Journal ingestion is intentionally absent.

After the Operator saves the initial Grafana credential, run the reviewed
`central/finalize-credential-handoff.sh` inside the central guest. It removes
the plaintext Grafana bootstrap value and retains only the mode-`0600` ingest
credential needed for deliberate future collector enrollment.
