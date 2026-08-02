# Wazuh Durable Notifications A4c Review

Status: accepted. Deterministic verification, live baseline seeding, exact timer
installation, and the controlled Operator listening test pass.

## Candidate evidence

- A dedicated level-10+ query supplies notification candidates.
- Initial live polling seeded existing high-priority IDs without playback.
- Durable state and last-run receipts are mode `0600`.
- Pending records omit descriptions and raw payload fields.
- Static F3/M3 security phrases are tracked and bounded WAV files.
- Busy or closed Voice Presence defers delivery; idle Presence permits one
  cooldown-batched notice.
- The service reserves a batch before playback, favoring no duplicate speech
  over automatic replay after an ambiguous audio failure.
- Dashboard exposes read-only notification status only; it cannot trigger the
  poll or grant response authority.
- The installed timer and oneshot match the reviewed unit text, are enabled,
  and completed an immediate live poll successfully with no historical replay.
- The live receipt reported no pending alert, no attempted playback, no raw
  payload retention, and no remediation authority.
- An isolated post-baseline synthetic high-priority event exercised the real
  notification service and static audio path without writing a fake Wazuh event
  or changing the production cursor. Exactly one batch was attempted and
  played, and the Operator confirmed the generic notice was audible.

## Verification

```bash
make verify-wazuh-alert-notifications
make verify-wazuh-alert-notification-deployment
ruby scripts/verify-notification-cues-a1.rb
```

## Human review outcome

- Accepted by the Operator on 2026-08-02 after hearing the single controlled
  privacy-safe cue.
