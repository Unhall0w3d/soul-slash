# Crucible Network-Device Syslog A0 Review

## Candidate

```text
status: deployed_and_verified
date: 2026-09-03
risk: Class 3 persistent private-LAN receiver and security-event transport
human brief approval: granted in the active recovery conversation
live deployment approval: granted in the active recovery conversation
human review outcome: approved in active recovery conversation
```

## Implementation summary

Crucible now receives UDP syslog only on its private address from the exact
Lattice and Loom source addresses. Rsyslog routes each sender to a fixed,
root-owned file under `/var/log/network-devices`. Logrotate bounds retention,
and a status helper reports attention above 2 GiB without deleting data.

Crucible's existing Wazuh agent passively follows the fixed log-file glob. No
Active Response, remote mutation, arbitrary relay, TCP/TLS listener, or backup
volume integration was added. Lattice and Loom were enabled one at a time and
verified by live events. Loom's running configuration was copied to its
startup configuration.

## Files changed

```text
- deploy/network-syslog/crucible/10-soul-network-devices.conf
- deploy/network-syslog/crucible/soul-network-devices.logrotate
- deploy/network-syslog/crucible/soul-network-syslog-status
- deploy/network-syslog/crucible/wazuh-localfile.xml
- deploy/network-syslog/crucible/install.sh
- scripts/verify-crucible-network-syslog-a0.rb
- docs/soul/CRUCIBLE_NETWORK_DEVICE_SYSLOG_A0_BRIEF.md
- docs/assessments/CRUCIBLE_NETWORK_DEVICE_SYSLOG_A0_REVIEW.md
- Makefile
```

## Commands and deterministic results

```text
make verify-crucible-network-syslog
PASS: all static receiver, firewall, rotation, Wazuh, bounded-queue, and
      status-helper checks

git diff --check
PASS

sudo bash /tmp/soul-network-syslog-a0-20260903/install.sh
PASS: Fedora rsyslog 8.2604.0 installed; rsyslog and Wazuh syntax checks passed

ss / firewalld / installed-file validation
PASS: UDP/514 bound only to 192.168.124.2; exact accept sources are
      192.168.124.10 and 192.168.124.11; installed candidate digests matched

Lattice login/logout event
PASS: lattice.log created, 631 bytes

Loom remote host configuration and startup-config copy
PASS: UDP/514 informational target 192.168.124.2; loom.log created, 624 bytes

/usr/local/libexec/soul-network-syslog-status
PASS: healthy, retained_bytes=1255, limit_bytes=2147483648

Wazuh agent logcollector evidence
PASS: wildcard discovery recorded for lattice.log and loom.log

Wazuh logcollector state
PASS: Lattice and Loom records target the agent with zero drops; Loom consumed
      the bounded failed-authentication probe

Vigil indexed-alert query
PASS: the approved custom decoder/rule set emitted authoritative managed-switch
      alerts under agent crucible
```

Rollback evidence is retained on Crucible at
`/var/lib/soul-network-syslog/rollback-20260903T080958Z`. The dedicated
`/srv/soul-backup` filesystem was not modified.

## Local LLM evals

Not applicable. This is deterministic infrastructure configuration rather than
a conversational behavior or intent-routing change.

## Memory and lifecycle

```text
Shared memory keys read: none
Shared memory keys written: none
Skill-private memory: none
Lifecycle states: complete
```

## Safety and persistence check

```text
Persistent service added: rsyslog explicitly approved
Existing persistent service changed: Wazuh agent localfile input explicitly approved
Daemon added: rsyslog explicitly approved
Watcher added: no
Scheduled task added: no; existing system logrotate facility used
Cron job added: no
systemd unit added: no custom unit; Fedora package service enabled as approved
Long-running background loop added: no
Background polling added: no
Confirmation gate weakened: no
Skill-private memory store added: no
```

## Known weaknesses and deferred scope

- Wazuh logcollector discovery, consumption, agent targeting, zero-drop
  forwarding, decoding, and authoritative alert indexing are proven.
- Daily rotation and compression are now observed on the live receiver.
  A forced 50 MiB threshold rotation has not been exercised.
- The ASUSWRT-Merlin gateway remains excluded until its sender behavior is
  separately reviewed.
- UDP syslog is intentionally unauthenticated and unencrypted on the private
  LAN in A0. The exact source firewall and rsyslog allowlists limit exposure
  but do not provide cryptographic sender identity.

## Privileged read-only acceptance — 2026-09-24

The Operator entered Crucible's sudo password directly in a visible terminal;
no password was placed in chat, command arguments, or the review record. The
bounded read-only check found:

- the `soul-crucible` zone with exactly the two approved UDP/514 rich rules,
  from `192.168.124.10` and `192.168.124.11`, in both active and permanent
  firewalld state;
- the required Wazuh localfile location, `syslog` format, and
  `only-future-events=yes` settings in the root-owned agent configuration;
- 14,466 bytes retained under `/var/log/network-devices`, with the installed
  status helper reporting healthy against its 2 GiB threshold;
- current Lattice and Loom files and dated rotations, including compressed
  prior-day archives; inspected files are `root:root` and mode `0640`.

This check read metadata and configuration only. It did not print raw syslog
messages, send packets, rotate logs, alter sender settings, or change Crucible.
The transient terminal capture was owner-only and removed after these results
were recorded. Earlier Wazuh forwarding and indexed-alert evidence remains the
2026-09-03 live record; it was not repeated in this read-only check. The
unprivileged status-helper invocation cannot measure the root-owned directory,
so operational checks must invoke it with root authority.

## Human review checklist

```text
[x] Matches approved brief
[x] No unapproved scope expansion
[x] Approved persistence is bounded and correctly documented
[x] Risk class is correct
[x] Confirmation gates are intact
[x] Deterministic tests are meaningful
[x] Failure and rollback behavior are predictable
[x] Live Lattice and Loom evidence is sufficient
[x] Bounded Wazuh decoder/rule coverage emits an indexed managed-switch event
[x] ASUSWRT-Merlin remains outside A0 until separately reviewed
```

## Human review outcome

```text
Outcome: approved
Reviewer: Operator
Date: 2026-09-24
Decision summary: Approved closing the pending Crucible review after the live
  read-only receiver, firewall, Wazuh input, capacity, and rotation checks;
  approved inclusion of the site-specific deployment files in the later
  commit and merge after the remaining Soul work is complete.
Required changes: none for the reviewed A0 scope
```

## Reconciliation assessment — 2026-09-24

The candidate header records historical deployment and approval assertions,
while the final Operator review outcome was still `pending` at that stage.
The historical claim did not fill that explicit outcome field. The subsequent
privileged read-only acceptance and Operator decision above closed the review.

The static verifier passed again. A read-only SSH check found Crucible, active
`rsyslog` and `wazuh-agent` services, the listener on
`192.168.124.2:514`, and the installed receiver and rotation files. SHA-256
values of the installed rsyslog, logrotate, and status-helper files match the
three local candidate files exactly. The root-owned Wazuh configuration and
network log directory were inaccessible to the unprivileged SSH account;
read-only firewalld inspection was also denied by polkit. The installed status helper exits before reporting
retained bytes when `du` lacks permission; its current capacity status is
therefore unverified in this check. No configuration, firewall, sender, log,
or service was changed.

Those were the remaining checks at this stage. The privileged acceptance
and Operator decision below resolve them for the reviewed A0 scope. Source
inclusion is scheduled with the later baseline commit and merge.
