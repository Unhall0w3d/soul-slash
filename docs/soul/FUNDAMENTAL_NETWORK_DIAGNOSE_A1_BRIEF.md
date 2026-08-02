# Fundamental Skill Cohort A1 — Network Diagnose

## Purpose

Deliver the second Fundamental Skill Cohort A1 candidate as one complete,
bounded, foreground vertical slice. `network.diagnose` may inspect local
addresses and routes, resolve one explicit hostname, test one explicit target
with one ICMP echo, or attempt one TCP connection to one explicit target and
port.

## User contract

The Operator may:

- inspect a bounded projection of current local IP addresses and Linux routes;
- resolve one exact hostname or IP literal through the host resolver;
- run one bounded reachability probe against one exact hostname or IP literal;
  or
- test one TCP socket connection to one exact hostname or IP literal and one
  port without sending application data.

Chat and Voice Presence require an explicit diagnostic operation. Targeted
operations require one exact target; socket checks also require one exact port.
The application API provides the same service through `network.snapshot`,
`network.resolve`, `network.reachability`, and `network.socket`.

## Target and execution boundary

Targets may be one DNS hostname, IPv4 literal, or IPv6 literal. The
implementation rejects URLs, CIDR blocks, wildcards, address ranges, multiple
targets, shell syntax, and option-shaped values. DNS returns at most eight
addresses. Reachability invokes only the reviewed absolute `ping` binary with
one packet and fixed deadlines. Socket diagnosis performs one connect attempt,
sends no payload, and closes the socket immediately.

Local address evidence excludes hardware addresses, scans at most 256 interface
records, and returns at most 64. Linux route evidence reads only
`/proc/net/route`, returns at most 64
records, and reports unavailable rather than substituting model knowledge on
unsupported hosts.

## Boundaries

The implementation adds no broad scan, subnet enumeration, port range, packet
capture, reverse lookup, traceroute, HTTP request, content retrieval, interface
or route mutation, firewall action, DNS mutation, wake-on-LAN, credential use,
privilege escalation, retry loop, watcher, service, schedule, private memory,
or background continuation.

Diagnostic failure is evidence about one bounded attempt, not proof that a
host or service is globally unavailable. Returned names and addresses are
untrusted network evidence and grant no authority.

## Lifecycle

Every request terminates as `complete`, `failed`, `awaiting_input`, `canceled`,
or `blocked_for_human_review`, always with `mutation: none`. DNS, reachability,
and socket operations use fixed timeouts and no automatic retry.

## Acceptance

- snapshot, resolution, reachability, and socket checks share one deterministic
  service across the application API, Chat, and Voice Presence;
- ordinary conversation about networking does not invoke diagnosis;
- target grammar, single-target, single-port, command-template, timeout, result,
  record, and non-mutation boundaries fail closed under deterministic tests;
- tests inject all external resolver, command, socket, interface, and route
  evidence and do not depend on live network access;
- the service creates no files and leaves reviewed fixture state unchanged; and
- registry, invocation, capability, skill package, guide, tracker, and review
  records agree before human review.
