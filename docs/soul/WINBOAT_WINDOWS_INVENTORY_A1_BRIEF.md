# WinBoat Windows Inventory A1 Brief

## Human direction

Represent the Operator's Windows 11 work environment as its own fleet identity
without exposing it directly to the LAN, changing its acquired guest address,
or granting Windows lifecycle authority. The dashboard remains the remote
interaction surface; all evidence collection originates on the workstation.

The deployment name is **Chancery**. Its private logical FQDN and fixed WinBoat
guest address remain local configuration rather than public defaults.

## Approved scope

A1 may:

- add one optional built-in `inventory_only` fleet identity;
- inspect one validated local Docker container name;
- read only fixed-format container state, restart count, image, isolated Docker
  address, and published-port bindings;
- resolve the running bindings for WinBoat's Windows RDP and guest service;
- make bounded TCP connection probes only to validated `127.0.0.1` bindings;
- display the configured private FQDN, guest address, service state, and
  observation time;
- add a host-local inventory relationship from the workstation; and
- refresh only that card through the existing device refresh operation.

## Explicit exclusions

A1 must not:

- inspect or return the container environment, Compose file, credentials,
  command line, mounts, logs, Windows data, or RDP session content;
- execute a command inside the container or Windows guest;
- start, stop, restart, reboot, update, or reconfigure Docker or Windows;
- add Maintenance or Reboot controls;
- publish a port beyond loopback, create a DNS record, or change Docker,
  Windows, firewall, routing, DHCP, or Pi-hole configuration;
- claim that the internal guest address is LAN-routable; or
- create a daemon, listener, polling loop, or new timer.

## Read-only adapter contract

The adapter uses fixed `/usr/bin/docker` argument vectors only:

- one formatted container-state inspection;
- one formatted `winboat_default` address inspection;
- one formatted published-port inspection; and
- fixed `docker port` resolution for `3389/tcp` and `7148/tcp`.

The broad Docker object is never serialized. All declared bindings must use
`127.0.0.1`; the resolved RDP and guest-service ports must remain inside their
reviewed WinBoat Compose ranges. Any missing, malformed, public, wildcard, or
unexpected binding fails closed to unavailable/attention evidence. Probe output
is not persisted.

## Configuration

Public defaults keep the adapter disabled and omit a deployment FQDN. An
Operator enables it only in ignored local configuration:

```text
SOUL_FLEET_CHANCERY_ENABLED=true
SOUL_FLEET_CHANCERY_LABEL=Chancery
SOUL_FLEET_CHANCERY_FQDN=<private logical FQDN>
SOUL_FLEET_CHANCERY_GUEST_ADDRESS=<private WinBoat guest address>
SOUL_FLEET_CHANCERY_CONTAINER_NAME=WinBoat
```

The address is descriptive identity evidence. Enabling this adapter performs no
network mutation.

## Risk classification

A1 is a Class 2 host-local read. It adds no device mutation authority and no
new network exposure.
