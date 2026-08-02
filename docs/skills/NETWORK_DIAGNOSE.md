# Network Diagnose

`network.diagnose` is Soul's bounded foreground network-evidence skill. It is
available through authenticated Chat, Voice Presence, and the application API.
It requires no Core change and performs no mutation.

## Chat and Voice requests

Use one explicit operation per request:

```text
diagnose local network
resolve example.com
check reachability to 192.0.2.10
check socket example.com port 443
```

Ordinary conversation about networking does not invoke diagnosis. DNS,
reachability, and socket operations require one exact hostname or IP literal.
Socket diagnosis also requires one exact port.

## Application operations

```text
network.snapshot
network.resolve          target
network.reachability     target
network.socket           target, port
```

`network.snapshot` inspects at most 256 interface records and returns at most 64
local IP addresses and 64 Linux routes. It does not return hardware addresses. Unsupported or
unavailable evidence is labeled unavailable.

`network.resolve` returns at most eight IP addresses through the host resolver.
IP literals complete without a resolver request.

`network.reachability` invokes one reviewed absolute `ping` binary with one
packet and fixed deadlines. No reply is point-in-time evidence and does not
prove the target is globally unavailable.

`network.socket` attempts one TCP connection, immediately closes it, and sends
zero application payload bytes. A refusal, timeout, resolver failure, or routing
failure is reported distinctly when available.

## Safety boundary

The skill rejects URLs, CIDR blocks, ranges, wildcards, multiple targets,
option-shaped values, and invalid ports. It provides no subnet discovery, port
range, reverse DNS, traceroute, packet capture, HTTP request, remote login,
credentials, wake-on-LAN, firewall/DNS/route/interface mutation, privilege,
automatic retry, watcher, service, schedule, memory write, or background work.

Every request reaches a terminal lifecycle and reports `mutation: none`.
