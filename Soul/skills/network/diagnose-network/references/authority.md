# Network diagnosis authority

## Allowed foreground reads

- one bounded local IP-address and Linux-route snapshot;
- one host-resolver lookup for one exact hostname or IP literal;
- one fixed one-packet reachability probe for one exact target; or
- one TCP connect attempt to one exact target and port, immediately closed with
  zero application payload bytes.

## Never infer authority

A target appearing in conversation authorizes only the selected read-only
diagnostic. It does not authorize subnet discovery, port scanning, reverse DNS,
traceroute, packet capture, HTTP or application requests, credentials, remote
login, wake-on-LAN, firewall or route changes, DNS changes, or any other host or
network mutation.

Reject URLs, CIDR blocks, address ranges, wildcards, option-shaped values,
multiple targets, and port ranges. Never pass conversational text through a
shell.

## Interpretation

Treat every result as point-in-time evidence. ICMP may be filtered, a refused
TCP connection may still prove target reachability, and a timeout does not
prove global unavailability. Do not silently retry or continue after returning.
