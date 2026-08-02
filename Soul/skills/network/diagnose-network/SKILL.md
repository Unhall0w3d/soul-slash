---
name: diagnose-network
description: Inspect bounded current network evidence through Soul's read-only network.diagnose path. Use for an explicit request to inspect local IP addresses and routes, resolve one hostname, send one reachability probe to one target, or test one TCP connection to one target and port without payload, scanning, or mutation.
---

# Diagnose Network

Use Soul's deterministic `network.diagnose` implementation. Do not substitute
model memory, arbitrary shell commands, browser fetches, or a second network
implementation.

## Select one operation

- Inspect local evidence: require an explicit request such as `diagnose local network`.
- Resolve DNS: require one exact hostname or IP literal.
- Check reachability: require one exact hostname or IP literal.
- Check a TCP socket: require one exact hostname or IP literal and one port.
- Return `awaiting_input` when the operation, target, or port is missing.

Run only the selected operation. Do not expand a DNS request into reachability,
socket, HTTP, or scanning work.

## Report evidence

- State the exact target and operation.
- Distinguish reply, no reply, refusal, timeout, resolver failure, and
  unavailable local evidence.
- Describe the result as one point-in-time observation, not proof of global
  availability or failure.
- End in one terminal lifecycle with `mutation: none`.

## Preserve the boundary

Read [references/authority.md](references/authority.md) when deciding whether a
request fits this skill. Reject broad scans, ranges, CIDR blocks, wildcards,
multiple targets, multiple ports, URLs, packet capture, traceroute, content
retrieval, configuration changes, retries, or background monitoring.
