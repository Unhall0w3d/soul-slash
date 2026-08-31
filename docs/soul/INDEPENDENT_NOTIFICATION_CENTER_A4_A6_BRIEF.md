# Independent Notification Center A4-A6 Brief

## Authority

The Operator approved separating Soul's notification system from Voice
Presence on 2026-08-31. This brief authorizes a candidate user service, but its
installation still requires review of the exact generated unit digest and the
confirmation phrase `INSTALL_SOUL_NOTIFICATION_CENTER`.

## Objective

Deliver Soul's existing static cues and pre-generated notices when Voice
Presence is closed. Voice Presence remains an optional microphone and spoken
conversation surface, not the notification runtime.

## Runtime contract

- One local `soul-notification-center.service` follows the user manager's
  active `default.target`. Atelier does not activate `graphical-session.target`
  and has user lingering enabled, so the service may remain ready across a
  graphical logout; it still stops with the user manager or explicit disable.
- The service observes only the standard desktop-notification D-Bus method and
  dispatches allowlisted static notification events through a bounded CLI.
- It has no network listener, model or Core dependency, notification-content
  store, command authority, response action, or dynamic speech synthesis.
- It restarts only on failure with systemd start limiting.
- Dashboard events call authenticated, CSRF-bound status, settings, and
  delivery endpoints. Persistent hashed event keys prevent duplicate delivery
  across Dashboard reloads.

## Voice collision contract

Voice Presence publishes only its existing lifecycle receipt. Notification
Center checks that receipt at delivery time. If Voice Presence is hearing,
thinking, speaking, paused, failed, or holding a follow-up window, a static cue
may play but the spoken notice is suppressed. Closing Voice Presence does not
disable cues or spoken notices.

Notification voice and mode belong to Notification Center. The reviewed modes
remain `voice`, `priority`, `cues`, and `muted`; voices remain F3 and M3.

## Desktop observation contract

The existing metadata-only classifier remains authoritative for the first
cohort. The observer uses application identity, desktop entry, urgency, and
category. It does not retain or forward title, body, image, action, reply,
sender, or history content. Browser-originated sites are not inferred.
Noctalia remains the visual notification daemon.

## Wazuh contract

The existing bounded Wazuh timer retains its baseline, level threshold,
cooldown, event-ID cursor, and privacy limits. It now submits the generic
`security_alert` event to Notification Center. Delivery remains notification
only and grants no acknowledgement, suppression, quarantine, deletion,
remediation, or Active Response authority.

## Lifecycle and retention

Each delivery terminates as `complete`, `failed`, or `awaiting_input`.
Settings and at most 256 SHA-256 event-key digests are stored owner-private.
Notification content, audio input, model output, and desktop-notification
payloads are not retained. Uninstalling the service leaves owner settings in
place and does not change Voice Presence.

## Acceptance

- deterministic checks prove closed-Presence spoken delivery, active-Presence
  collision suppression, modes, voice selection, persistent deduplication,
  private state, and allowlisted events;
- deployment checks prove exact digest binding, the live user-manager target,
  start limiting, local-only address families, and no model/Core dependency;
- Dashboard, Wazuh, Voice Presence, notification-cue, and desktop-classifier
  regressions pass;
- live acceptance requires exact service installation, one Dashboard
  completion with Voice Presence closed, one collision test while it speaks,
  one urgent desktop test, and Operator audio review.

## Excluded

Dynamic spoken content, arbitrary event names, remote push delivery, mobile
notifications, notification history, notification actions, automatic replies,
LLM-authored notices, and notification-triggered system mutation remain out of
scope.
