# Cisco Phone Fleet Status D1 Brief

## Human direction

Add the Operator's Cisco 8851 Webex Calling phone to the Administration fleet
surface. Track and expose what the phone safely makes available, while accepting
that it has less local management authority than Maven, Forge, or Pi-hole.

The deployment address is private machine configuration. It must not be committed
to the public repository.

## Approved slice

This slice may:

- add an optional, environment-configured Cisco phone inventory entry;
- perform one bounded, read-only reachability probe during an explicit or
  scheduled fleet-status collection;
- display the configured model, Webex Calling role, reachability, and lifecycle
  ownership;
- represent the phone and Webex Calling in the evidence-derived topology;
- make existing fleet display addresses portable through ignored environment
  configuration;
- document optional richer read-only enrichment when phone web access is enabled.

This slice must not:

- add the phone to device mutation, maintenance, or reboot targets;
- attempt authentication, provisioning, registration changes, calling actions,
  factory reset, firmware changes, or remote control;
- retain a directory number, user identity, MAC address, serial number,
  credentials, call history, device logs, or raw phone web-page content;
- assume that reachability proves Webex registration or call readiness;
- broaden the existing collection schedule or create a new persistent process.

## Runtime contract

- The phone is absent unless explicitly enabled.
- An enabled phone requires one syntactically valid IPv4 address or hostname.
- The probe runs as an argument-vector command with a short timeout and no shell.
- One collection ends in `complete` or `failed`; no probe continues afterward.
- An unreachable phone remains visible as offline without hiding other fleet
  evidence.
- The dashboard marks the device `status_only` and renders no mutation actions.

## Current evidence boundary

The initial Maven probe found the configured phone reachable by ICMP. HTTP and
HTTPS were closed. Cisco documents read-only Product Information and Status
surfaces when phone web access is enabled, but D1 does not require or attempt to
enable that interface.

## Risk

Class 1 read-only local evidence with a private status-cache mutation. The phone
address belongs in ignored local configuration; public defaults contain no
Operator-specific network addresses.
