# Fleet Device Refresh A2 Brief

## Intent

Make freshness visible and actionable on each Guided Maintenance device card
without recollecting or mutating the entire fleet.

## Approved slice

- Add one **Refresh** control to every fleet card.
- Refresh exactly the selected device through its existing bounded collector.
- Preserve every other device's prior evidence.
- Atomically replace the private fleet snapshot after success.
- Show a per-device **Checked** timestamp.
- Recompute summary and topology from the combined snapshot.
- Keep status-only and inventory-only devices free of maintenance and reboot
  authority.

## Bounds

- The operation requires one validated device ID already present in the
  current private fleet snapshot.
- It performs no subnet discovery and no automatic retry.
- Status-only devices receive one bounded reachability probe.
- Existing SSH inventory devices retain their fixed alias and fixed command
  constraints.
- The request terminates as `complete` or `failed`.
- No background process, watcher, timer, credential, or new network listener is
  introduced.
- No vendor-specific firmware, WAN, client, registration, or cloud state is
  inferred from reachability.

## Interface

Application operation:

```text
maintenance.fleet.device.refresh
  device_id: <existing fleet device ID>
```

Dashboard:

```text
Administration → Guided Maintenance → device card → Refresh
```

## Acceptance

- A full collection records an observation time for each device.
- Refreshing an enrolled status-only appliance invokes only one reachability
  probe for that appliance.
- Other fleet cards remain present and unchanged.
- The refreshed card and private snapshot contain the new observation time.
- Summary and topology reflect the replaced card.
- Invalid or stale device IDs fail safely.
- The Dashboard identifies that only one device was probed.
