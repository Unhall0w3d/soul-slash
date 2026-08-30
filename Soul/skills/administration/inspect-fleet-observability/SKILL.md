---
name: inspect-fleet-observability
description: Read Soul's bounded Observatory summary when the Operator explicitly asks about fleet health, fleet telemetry, or Observatory status. Do not use for maintenance, reboot, arbitrary metrics queries, or remediation.
---

# Inspect Fleet Observability

Use Soul's registered `fleet.observability` path. Do not substitute model
memory, arbitrary PromQL, shell commands, direct Grafana queries, or a second
telemetry implementation.

1. Require an explicit fleet-health, fleet-telemetry, or Observatory-status
   question. Ordinary discussion of servers or monitoring remains
   conversational.
2. Run the one bounded foreground summary from the fixed query registry.
3. Report endpoint freshness, resource pressure, storage and network
   exceptions, switch or interface health, alerts, boot evidence, and explicit
   gaps only when returned by that summary.
4. Offer the owner-configured Grafana drill-down when it is present.
5. Distinguish unavailable evidence from healthy evidence. Do not infer root
   cause or claim that an action was performed.

The skill terminates `complete` or `failed` with `mutation: none`. It cannot
accept arbitrary PromQL, return raw samples or journal messages, run
maintenance, reboot devices, change switches or alerts, notify, retry in the
background, or remediate.
