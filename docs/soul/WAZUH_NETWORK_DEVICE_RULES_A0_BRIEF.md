# Wazuh Network-Device Rules A0 Brief

```text
date: 2026-09-03
status: deployed; later review records live event acceptance passed
live deployment authorized: yes, in active recovery conversation
risk: Class 3 security-event classification on Vigil
```

## Objective

Close the final Crucible network-syslog acceptance gap by teaching Vigil to
decode the fixed Cisco/Netgear message envelope already forwarded by the
Crucible Wazuh agent. Emit bounded indexed evidence without changing collection,
Active Response, notifications, or any device.

## Boundary

- Match only messages containing the exact `%FACILITY-SEVERITY-CODE:` shape.
- Extract the emitting IPv4 address, facility, one-letter severity, event code,
  and message body.
- Emit routine device events at Wazuh level 3.
- Elevate warning/error severity to level 7.
- Treat individual `SNMPAUTHFAIL` events as counting-only and emit level 8 only
  after a repeated event, with a fifteen-minute suppression window.
- Use custom rule IDs 100100 through 100103; current Vigil custom rules use only
  ID 100001.
- Validate with `wazuh-logtest` before restarting `wazuh-manager`.
- Restart only `wazuh-manager`, confirm all manager components return healthy,
  then generate one bounded switch event and confirm it is indexed.

## Exclusions

No Active Response, email/voice notification policy, raw-event archival,
manager enrollment, device mutation, firewall change, or log-retention change.
Deployment stops on decoder, rule, configuration, or health-check failure.

## Acceptance

1. Representative Loom and Lattice samples match the custom decoder in
   `wazuh-logtest`.
2. Routine, warning, and SNMP-authentication samples select the intended rule
   IDs and levels.
3. The existing rule 100001 remains unchanged.
4. A live event appears under agent `crucible` in `wazuh-alerts-*`.
5. No Active Response or notification behavior changes.
