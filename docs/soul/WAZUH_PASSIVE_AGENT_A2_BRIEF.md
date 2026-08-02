# Wazuh Passive Agent A2 Brief

## Status

```text
central_a1_accepted: yes
single_endpoint_pilot_authorized: yes
cohort_expansion_authorized: no
active_response_authorized: no
clamav_authorized: no
automatic_remediation_authorized: no
human_live_review_required: yes
```

## Purpose

Qualify one passive Wazuh Linux agent against the accepted private central
platform before any wider fleet rollout. A2 measures connection, inventory,
file-integrity initialization, resource cost, persistence, and failure behavior
without granting response or remediation authority.

Deployment-specific names, addresses, keys, agent identifiers, firewall
sources, and live findings remain in ignored owner-local receipts.

## Pilot contract

The pilot endpoint must be a supported 64-bit Linux system with:

- an exact, signature-verified Wazuh agent matching the central release;
- one reviewed manager identity supplied outside tracked source;
- TCP event transport restricted to the exact pilot endpoint;
- enrollment access opened only for enrollment and closed immediately after;
- the Wazuh package repository disabled after installation;
- agent startup enabled and the service active;
- Active Response explicitly disabled on the endpoint;
- no automatic quarantine, deletion, firewall mutation, account mutation,
  package mutation, process termination, or reboot authority.

The central manager may retain its vendor command definitions, but it must not
assign an active-response command to the pilot. The endpoint-side disabled
setting is an independent defense boundary.

## Initial collection boundary

A2 accepts the vendor's supported passive inventory, vulnerability,
configuration-assessment, rootcheck, journal/log collection, and conservative
file-integrity defaults for the pilot. It does not add owner home directories,
model stores, generated media, VM storage, backup repositories, or other
high-churn trees.

Initial inventory and file-integrity scans may briefly consume CPU. The review
must distinguish that bounded startup work from settled service overhead and
must stop expansion if unexplained sustained load, disk growth, event volume,
or endpoint instability appears.

## Installation and enrollment

Use the official Wazuh package channel documented for the endpoint family.
Verify the installed package signature and exact version. Disable the package
repository after installation so ordinary endpoint maintenance cannot drift
the agent away from the manager version.

Open registration only from the exact pilot endpoint and only long enough to
obtain the agent key. Close registration immediately afterward. Keep encrypted
agent-event transport open only from the enrolled endpoint.

## Verification

A2 must prove:

- exact supported endpoint identity and kernel;
- signed agent package and exact manager-compatible version;
- disabled package repository;
- active and enabled service with no failed systemd units;
- manager reports the agent Active after a service restart;
- initial file-integrity collection completes;
- endpoint establishes the expected event connection;
- registration is closed after enrollment;
- Active Response is explicitly disabled on the endpoint and unassigned on the
  manager;
- bounded disk and memory footprint is recorded;
- no credential, enrollment key, address, or live finding enters Git.

The Operator must then inspect the endpoint in the Wazuh dashboard and decide
whether the data is useful and the initial findings are tolerable. Passing
machine checks does not authorize cohort expansion.

## Known gate between pilot and expansion

Endpoint privilege drift discovered during installation is not repaired inside
this pilot. Any broad passwordless sudo rule must receive a separate exact
hardening review so the accepted digest-bound maintenance authority remains
functional while unintended general root authority is removed. Cohort
expansion is blocked until that defect is resolved or explicitly accepted.

## Rollback

Rollback stops and disables only the exact pilot agent, removes its central
registration after human review, removes the endpoint-specific event firewall
rule, and removes the exact package through the supported package manager.
Rollback must not alter central retention, other fleet maintenance authority,
endpoint backups, or unrelated services.

## Excluded from A2

- additional endpoint agents;
- Active Response or any automatic remediation;
- ClamAV installation or scans;
- Soul API credentials or Dashboard integration;
- Wazuh automatic upgrades;
- central index backup or restore;
- security alert acknowledgement or closure.
