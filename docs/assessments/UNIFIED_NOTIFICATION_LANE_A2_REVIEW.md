# Unified Notification Lane A2 Review

## Candidate

The Dashboard now has a single static-asset notification vocabulary for
creative candidates, improvement reviews, fleet state transitions, and
backup/recovery outcomes. It adds an `Alerts Priority` delivery mode and keeps
all detailed evidence in the authenticated Dashboard.

## Files changed

- `assets/dashboard/dashboard.js`
- `assets/notifications/*.wav`
- `lib/soul_core/dashboard_http_application.rb`
- `scripts/build-notification-audio`
- `scripts/verify-notification-cues-a1.rb`
- `docs/soul/UNIFIED_NOTIFICATION_LANE_A2_BRIEF.md`

## Verification

- `ruby scripts/verify-notification-cues-a1.rb`
- `node --check assets/dashboard/dashboard.js`
- `ruby -c lib/soul_core/dashboard_http_application.rb`

## Lifecycle and risk

- Lifecycle: `complete` or `failed` at the originating foreground Dashboard
  action; no notification work persists afterward.
- Memory keys: none.
- Risk: low. Notifications are local static audio and browser state only.

## Human review checklist

- [ ] Verify `Alerts Priority` speaks only attention/reboot/backup-failure
  outcomes when Voice Presence is visibly idle.
- [ ] Verify full Voice speaks one review-ready notice for a newly completed
  music, visual, or improvement candidate.
- [ ] Verify the first fleet snapshot is silent and a later degradation uses
  the appropriate attention cue.
- [ ] Verify Cues and Muted do not speak.
- [ ] Confirm Wazuh's existing durable notifications remain unchanged.
