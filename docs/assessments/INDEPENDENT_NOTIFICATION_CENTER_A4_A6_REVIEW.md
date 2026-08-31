# Independent Notification Center A4-A6 Review

## Candidate summary

Notification delivery has been removed from Voice Presence and centralized in
one local allowlisted service. Dashboard and Wazuh use the same delivery
contract. Voice Presence contributes only a point-in-time collision signal.

## Files changed

- `lib/soul_core/notification_center_service.rb`
- `lib/soul_core/notification_center_deployment.rb`
- `lib/soul_core/dashboard_http_application.rb`
- `lib/soul_core/wazuh_alert_notification_service.rb`
- `assets/dashboard/dashboard.js`
- `scripts/soul-notification-center`
- `scripts/soul-notification-center-observer.py`
- `scripts/soul-notification-center-runtime`
- `scripts/soul-voice-presence-app.py`
- deterministic verifiers, Make targets, documentation, and timeline seed

## Lifecycle states

- delivery: `complete`, `failed`, `awaiting_input`
- deployment preview: `blocked_for_human_review`
- deployment mutation: `complete`, `failed`, `awaiting_input`

## Durable state

Owner-private settings store only mode, voice, schema, and timestamp. Delivery
state stores at most 256 hashed deduplication keys and the last delivery state.
No memory keys were added. No notification content is retained.

## Risk classification

Class 3 local persistent user service. It has no network listener, model or
Core dependency, privileged operation, response authority, or notification-
content retention. Installation is exact-digest and confirmation bound. The
unit uses Atelier's active `default.target`; the generic
`graphical-session.target` is inactive and user lingering is enabled.

## Known weaknesses

- The observer depends on `dbus-monitor` text framing and the existing narrow
  application classifier.
- Spoken collision prevention is a point-in-time receipt, not an audio mixer.
- The service does not reconstruct events missed while the user manager is
  stopped or the service is disabled.
- Browser site notifications remain unclassified unless the desktop metadata
  identifies an already reviewed application.

## Human review checklist

- [ ] Review the exact unit plan and digest.
- [ ] Install the exact candidate service.
- [ ] Close Voice Presence and confirm one Dashboard completion cue/notice.
- [ ] Speak through Voice Presence and confirm a concurrent notice does not
      overlap speech.
- [ ] Trigger a safe urgent Webex or Teams notification and confirm Noctalia
      remains visual authority while Soul adds only the reviewed static notice.
- [ ] Change modes and F3/M3 voice, reload the Dashboard, and confirm settings
      persist.
- [ ] Confirm no duplicate notice after a Dashboard reload.

## Validation

Passed locally on 2026-08-31:

```text
ruby scripts/verify-independent-notification-center-a4-a6.rb  # 20 checks
make verify-notification-cues
make verify-wazuh-alert-notifications
make verify-wazuh-alert-notification-deployment
make verify-wazuh-conversation-status
make verify-voice-presence
make verify-project-timeline
ruby scripts/verify-responsive-chat-and-web-research.rb
node --check assets/dashboard/dashboard.js
ruby -c (all changed Ruby runtime files)
python3 -m py_compile (all changed Python runtime files)
git diff --check
systemd-analyze --user verify (generated candidate unit)
```

The current Atelier-specific unit digest is
`bba5c1eac1f2a6592219356ceb4b08958edacbbbe2fad6fa4fc359aa9deb9c4b`.
It remains uninstalled pending exact human review.

The legacy Phase 12C and Music Studio A3 aggregate verifiers still reject an
existing bounded Chat delay and the canonical SVG namespace anywhere in the
shared Dashboard source. Those primitives predate and are unchanged by this
slice; the new Notification Center adds no browser timer, polling transport,
or remote URL. Its authenticated HTTP boundary is exercised directly by the
new verifier. Live installation and listening review remain pending.
