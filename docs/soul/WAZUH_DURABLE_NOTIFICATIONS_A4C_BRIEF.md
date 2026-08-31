# Wazuh Durable Notifications A4c Brief

## Objective

Deliver a durable, deduplicated, privacy-safe spoken security cue while the
Dashboard page is closed, without turning notification delivery into response
or remediation authority.

## Event contract

- The notifier uses a separate level-10+ candidate query so ordinary elevated
  alerts cannot crowd high-priority events out of the bounded window.
- The first run records a baseline and never speaks historical alerts.
- Only SHA-256 event identifiers, timestamps, levels, severity, and agent IDs
  enter the durable cursor. Descriptions, paths, users, IPs, and raw payloads do
  not enter notification state or receipts.
- Seen IDs survive process, Dashboard, and host restarts. Pending alerts expire
  after 24 hours and are bounded to 128 records.
- One generic batch notice is attempted at most once per reserved batch. A
  failure is recorded and is not automatically replayed.

## Delivery contract

- Voice notification is disabled by default in the private manifest.
- A4-A6 supersedes the original delivery dependency: the independent
  Notification Center accepts the generic event while Voice Presence is
  closed. Active Voice Presence suppresses only overlapping speech; the static
  cue remains eligible.
- A 15-minute cooldown batches new events and prevents alert storms from
  repeatedly speaking.
- F3 and M3 use static tracked WAV files saying only that Soul detected a
  high-priority security alert and the Operator should review Wazuh.
- No event-time synthesis, model call, dynamic alert phrase, acknowledgement,
  suppression, quarantine, deletion, retry, or Active Response exists.

## Closed-page deployment

An explicitly installed systemd user timer runs the bounded poll once per
minute after a two-minute boot delay, with ten seconds of randomized delay and
`Persistent=true`. The oneshot has a 45-second ceiling, an owner-private umask,
read-only home/system protection, and one write path for Wazuh cursor receipts.
Installation requires `INSTALL_SOUL_WAZUH_ALERT_NOTIFICATIONS`.

## Acceptance

- deterministic fixtures prove baseline seeding, durable deduplication,
  Presence deferral, cooldown batching, F3/M3 selection, disabled behavior,
  private state, and absence of remediation authority;
- live qualification seeds the current high-priority baseline with voice still
  disabled;
- final acceptance requires exact timer installation, one safe live cue test,
  and Operator listening/presentation review.
