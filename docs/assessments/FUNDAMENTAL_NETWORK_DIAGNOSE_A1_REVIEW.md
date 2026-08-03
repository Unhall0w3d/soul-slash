# Fundamental Skill Cohort A1 — Network Diagnose Review

Date: 2026-08-02

Branch: `codex/fundamental-network-diagnose-a1`

Status: human-approved; merge authorized

## Implementation

- `NetworkDiagnosticService` validates one target and owns all four operations;
- local evidence uses `Socket.getifaddrs` and a bounded read of
  `/proc/net/route`, with no shell command;
- DNS uses the host resolver with a fixed timeout and eight-result cap;
- reachability uses one absolute allowlisted `ping` binary, one packet, fixed
  argv, fixed deadlines, and no shell interpolation;
- TCP uses one bounded `Socket.tcp` connect and sends no application data;
- Chat and Voice Presence share exact deterministic controls;
- the application contract exposes `network.snapshot`, `network.resolve`,
  `network.reachability`, and `network.socket`; and
- registry-derived documentation was regenerated from the updated production
  registry rather than edited independently.

## Authority and privacy

Conversation selects one operation, one target, and—only for TCP—one port. It
cannot authorize a URL fetch, subnet or port scan, multiple targets, reverse
DNS, traceroute, packet capture, remote access, credentials, wake-on-LAN,
configuration mutation, privilege, retries, monitoring, or background work.

Target names, returned DNS records, and local address/route evidence are
untrusted point-in-time observations. A local snapshot may be retained in the
existing local conversation transcript, but no new memory or skill-private
store exists.

## Deterministic evidence

The focused verifier covers:

- bounded address scanning and returned evidence without hardware addresses;
- decoded Linux routes without a command;
- normalized, deduplicated, bounded hostname resolution;
- IP-literal resolution without resolver access;
- one exact ping argv and one attempt;
- one exact TCP connect with zero payload;
- URL, CIDR, range, wildcard, option, multiple-target, port-range, port-list,
  and invalid-port rejection;
- no-reply and connection-refused evidence;
- explicit Chat matches and ordinary-conversation restraint;
- deterministic orchestration, shared Chat/Voice response, and application
  envelope behavior.

All resolver, ping, socket, interface, and route inputs are injected. The test
suite does not depend on or contact the live network.

## Results

```text
make verify-fundamental-network-diagnose
19 checks passed

quick_validate.py Soul/skills/network/diagnose-network
Skill is valid

make verify-invocation-catalog
15 checks passed

make verify-operator-capability-catalog
passed

Phase 12B application API verifier
candidate-ready

Chat intent and interaction-boundary verifier
35 checks passed

documentation registry refresh and assistant skill catalog verifiers
passed

make test-soul
passed

local host smoke
snapshot: complete
localhost resolution: complete
127.0.0.1 reachability: complete, reply_received
127.0.0.1:4567 TCP: complete, connected, payload_bytes_sent 0
```

## Known weaknesses

- only Linux IPv4 route-table evidence is implemented;
- ICMP policy may make a reachable host appear non-responsive;
- exact natural-language grammar is deliberately conservative;
- single-label DNS follows host resolver policy; and
- local IP evidence becomes part of the requesting local transcript.

## Human review

The Operator approved this candidate on 2026-08-02 after reviewing command
construction, target and port rejection, point-in-time wording, privacy
expectations, zero-payload TCP behavior, ordinary-chat restraint, and the
absence of scanning, mutation, persistence, retries, or background work.
