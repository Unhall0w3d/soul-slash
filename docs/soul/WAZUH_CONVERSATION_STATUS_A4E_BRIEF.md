# Wazuh Conversational Status A4e Brief

## Objective

Let the Operator ask Soul a natural read-only security question through Chat or
Voice Presence and receive one bounded, privacy-filtered summary of the already
accepted Wazuh monitoring plane and recent-alert projection.

## Invocation boundary

- Explicit questions such as `How does security look?`, `Check Wazuh status`,
  and `Are there recent security alerts?` invoke the read.
- Topical statements such as `I am working on security` remain ordinary
  conversation.
- The invocation requires no approval because it is a bounded read. It performs
  one A4a collection and one A4b collection in the foreground using their
  existing timeouts, limits, credentials, tunnel, and owner-private caches.
- Voice Presence uses the ordinary Chat operation and therefore receives the
  same result and authority boundary. No separate voice command path exists.
- There is no retry, polling loop, automatic Core transfer, background work, or
  continuation after the response returns.

## Privacy-filtered result

The conversational result may include only:

- Wazuh manager state and required-daemon count;
- enrolled-agent aggregate counts;
- declared alert window, minimum level, total match count, returned count, and
  truncation state;
- aggregate elevated, high, and critical counts from the bounded result;
- latest normalized alert timestamp;
- the owner-reviewed adapted-posture score/count summary when configured;
- fresh, partial, unavailable, and last-successful timestamps.

It must not retain or speak normalized alert descriptions, rule IDs, event IDs,
paths, users, addresses, raw payloads, credentials, or private configuration.
ClamAV scan receipts are not centralized by A3, so the response states that
current ClamAV signature and latest-scan evidence were not collected rather
than inferring health.

## Authority boundary

Wazuh remains the authoritative investigation console. The invocation cannot
acknowledge, suppress, close, quarantine, delete, scan, remediate, isolate,
install, update, or otherwise mutate a host or Wazuh. Model output is not used
to synthesize or authorize the result.

## Acceptance

- deterministic fixtures prove explicit routing and reject topical mentions;
- fresh, partial, and unavailable results remain honest;
- the evidence record contains aggregates only and names all deliberately
  uncollected security fields;
- Chat returns deterministic content without model synthesis;
- Voice Presence reaches the same Chat tool ID;
- the production skill and invocation catalogs describe the no-remediation
  boundary;
- existing Wazuh, Chat, Voice, maintenance, and application tests pass.
