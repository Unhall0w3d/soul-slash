# Phase 12C Initial System Status Amendment

Status: human-approved implementation amendment

Authorization: on 2026-07-15 the human owner approved the Phase 12C dashboard and requested that system status populate automatically when the page opens while retaining manual Refresh.

## Approved behavior

- Perform one bounded `system_status.refresh` application call during dashboard bootstrap.
- Populate the existing system-status card from that result.
- Keep the existing Refresh button for later user-requested updates.
- Render an explicit failed/unavailable card state if initial collection fails without preventing Chat from loading.

## Boundaries

- One initial request per page load only.
- No timer, interval, polling loop, retry loop, watcher, worker, push channel, service worker, daemon, scheduler, or background continuation.
- No new host data categories and no change to the bounded host-status collector.
- No persistence, LAN exposure, remote request, or model authorization.

This amendment narrowly supersedes the Phase 12C brief's manual-only and no-automatic-initial-refresh language. All no-polling and foreground-only requirements remain in force.
