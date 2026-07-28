# Fleet DHCP Identity and Recovery A3 Brief

```text
date: 2026-07-28
human_authorization: approved in the active development conversation
implementation_authorized: yes
status-only automatic address retarget authorized: yes
SSH or mutation-authority automatic retarget authorized: no
one delayed ten-minute recovery attempt authorized: yes
risk: Class 2 private network identity and status-cache mutation
```

## Objective

Allow reviewed status-only devices to retain identity across DHCP address
changes without treating an IP address as permanent identity. Add a reversible
ignored-device list and remember the Operator's last successful discovery
subnet.

## Identity policy

Enrollment offers:

- `fixed`: the reviewed address remains authoritative;
- `dhcp_tracked`: one reviewed MAC address and private subnet become the stable
  identity for a status-only device.

`dhcp_tracked` is prohibited for SSH inventory or any mutation-capable device.
Locally administered MAC addresses must be disclosed during review. Duplicate,
missing, malformed, or ambiguous MAC evidence blocks automatic retargeting.

## Collection and recovery flow

For each DHCP-tracked status-only device:

1. Probe the recorded address once.
2. Compare the current local ARP identity with the reviewed MAC.
3. If the address is unavailable or belongs to another MAC, run one bounded
   host-discovery pass against the device's reviewed subnet.
4. If exactly one address has the reviewed MAC, update only that private
   status-only registry record, retain a bounded address-history event, and
   recollect its card.
5. If no match appears, mark the device offline and queue one recovery record.
6. Schedule one fixed transient user-level oneshot for ten minutes later.
7. The oneshot performs one final bounded recovery attempt and terminates.
8. A second miss clears pending recovery and waits for the next explicit or
   noon/midnight collection.

There is no sleeper, daemon, repeating ten-minute timer, polling loop, or
automatic retry beyond that single delayed attempt.

Devices sharing one subnet share one scan result per invocation. One collection
may scan no more than four distinct reviewed subnets, preventing a full
64-record registry from multiplying the 30-second recovery bound without
limit.

## Authority boundary

- Status-only DHCP address retarget changes private inventory state only.
- SSH inventory may report a possible changed address but must stop for human
  review.
- Maven, Proxmox, Pi-hole, and every mutation-capable target retain fixed
  addressing or reviewed DHCP reservations.
- A MAC match is identity evidence, not trust or mutation authority.

## Ignored devices

An authenticated Operator may preview and ignore one exact discovery
candidate. The private ignored record uses MAC identity when available and
falls back to the current IP otherwise. Ignored devices:

- are excluded from actionable candidate results;
- remain visible in a dedicated ignored list;
- may be restored through an exact digest-bound review;
- grant no trust, enrollment, or mutation authority.

## Privacy and persistence

Owner-private `0600` state may contain:

- the last canonical discovery subnet;
- reviewed DHCP MAC/subnet identity;
- a bounded address history;
- reversible ignored-device identity;
- one pending recovery record per reviewed DHCP device.

Raw scan output, the full neighbor table, unreviewed candidates, and service
fingerprints are never persisted or committed.

## Lifecycle

```text
discover → review → fixed | dhcp_tracked | ignored

dhcp_tracked check
  → verified_current
  → retargeted
  → retry_scheduled
  → recovered_after_delay | offline_until_next_check
  → blocked_for_human_review
```

Every invocation terminates as `complete`, `failed`, `awaiting_input`, or
`blocked_for_human_review`.

## Acceptance

- Last successful subnet refills after Dashboard reload.
- Enrolled and ignored identities are absent from actionable candidates.
- Ignoring and restoring are exact, reviewed, private mutations.
- DHCP tracking cannot be selected without reviewed MAC/subnet evidence.
- Current-IP MAC mismatch cannot be reported as healthy.
- Exactly one MAC match retargets only a status-only device.
- Zero or multiple matches never retarget.
- The delayed attempt is one fixed transient oneshot and never repeats.
- All registry, pending-recovery, and history state remains private and
  bounded.
