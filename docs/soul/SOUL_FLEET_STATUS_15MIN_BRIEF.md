# Soul Fleet Status 15-Minute Refresh Brief

The existing owner-level `soul-maintenance-fleet-status.timer` may collect
private, read-only fleet status every fifteen minutes. This changes only the
existing status-cache schedule. It does not authorize maintenance, reboot,
backup, credential, topology-discovery, or other mutation operations.

The service remains a bounded oneshot with the existing systemd sandbox and
private atomic snapshot path. Device cards may still request an independent
single-device refresh through the existing `maintenance_fleet_status_service`
path. The timer performs whole-fleet status collection; it does not become a
polling loop or grant fleet-wide maintenance authority.

Human review and installation remain at the existing schedule deployment gate:

```text
make fleet-status-schedule-plan
make fleet-status-schedule-install CONFIRM=INSTALL_SOUL_FLEET_STATUS_TIMER
make fleet-status-schedule-status
```

Candidate validation:

```text
ruby scripts/verify-maintenance-fleet-status-b1.rb
systemd-analyze calendar '*-*-* *:00/15:00'
```
