# Maintenance Device Control C1 Brief

```text
date: 2026-07-27
human_authorization: approved in the active development conversation
implementation_authorized: yes
scheduled_status_collection_authorized: yes
live_device_mutation_authorized: one supervised Forge maintenance transaction completed 2026-07-27; default gate remains off
risk: Class 5 privileged, remote-mutation, reboot, and scheduled-task candidate
```

## Outcome

Replace the separate A1, A2, and A3 cards beneath the maintenance control
plane with device-scoped controls on the Maven, Forge, and Pi-hole cards.
Every card exposes exactly two primary actions:

- **Maintenance**
- **Reboot**

An action is bound to one exact device. Selecting Pi-hole cannot authorize
Maven or Forge. Selecting Forge must disclose that a Forge reboot also
interrupts its Pi-hole LXC dependency.

The existing A1, A2, A2B, and A3 services remain backend safety components for
Maven. C1 changes their presentation and coordination; it does not weaken
their password, digest, terminal, reboot, or restoration boundaries.

## Persisted status

The newest normalized fleet snapshot is stored owner-private beneath:

```text
Soul/private/host_maintenance/fleet_status.json
```

The Dashboard loads this snapshot when Guided Maintenance opens. Manual
**Collect fleet status**, successful maintenance, and completed reboot
verification replace it atomically.

Status collection may also run through one reviewed owner-level systemd
oneshot and timer:

- at local noon;
- at local midnight; and
- persistently after a missed calendar event on the next login.

The collector unit terminates after one bounded invocation. The timer does not
start or authorize maintenance or reboot.

## Per-device maintenance

### Maven

Maven reuses the reviewed A2 visible-terminal workflow:

1. collect native package evidence through the registered desktop handoff;
2. review the exact Arch/AUR and applicable Flatpak plan;
3. authorize one digest;
4. enter the password only into native `sudo -v` in the visible terminal;
5. execute the existing bounded transaction;
6. invalidate the sudo ticket;
7. read the terminal receipt; and
8. collect and persist a new fleet snapshot.

### Forge

Forge uses only the fixed `proxmox-maintenance` SSH alias and fixed root
vectors for APT metadata refresh and full upgrade. It operates no guest,
performs no autoremove, answers no package-conflict question through model
output, and does not reboot automatically.

### Pi-hole

Pi-hole uses only the fixed `pihole-maintenance` SSH alias and fixed root
vectors for APT metadata refresh/full upgrade plus the reviewed Pi-hole update
command. It performs no autoremove and does not reboot automatically.

Remote maintenance runs in one foreground Dashboard request with a hard
deadline, one attempt, one global operation lock, a redacted receipt, and no
automatic retry. Completion triggers one fleet recollection.

The operation lock records its owner process identity, boot identity, and
process start identity. A verified live owner always blocks a second action.
An abandoned lock may be quarantined and reacquired once; an empty or malformed
lock remains authoritative for a short acquisition-race grace period before it
can be treated as stale. Lock cleanup must verify the original inode so it
cannot delete a replacement lock.

## Per-device reboot

Every reboot requires a fresh preview, exact device confirmation, and expected
digest.

### Maven

Maven reuses the reviewed A3 transaction and one-shot restoration boundary.
If A3 or its resume unit is unavailable, the Maven reboot button reports that
condition rather than introducing a simpler bypass.

### Forge and Pi-hole

The remote reboot coordinator:

1. records the target boot identity;
2. sends one fixed reboot request through the target's maintenance alias;
3. waits an initial bounded holdoff;
4. performs bounded fixed-target reconnect checks;
5. requires the device to return with a changed boot identity;
6. performs one full fleet recollection;
7. atomically updates the persisted snapshot and receipt; and
8. terminates.

There is no reboot retry. Failure to reconnect terminates
`blocked_for_human_review` with the prior snapshot retained and the target card
marked from the operation receipt.

## Dashboard behavior

- Device actions exist only on the normalized cards.
- A click opens device-specific review details; it is not immediate mutation.
- Only one maintenance or reboot operation may exist at once.
- The relevant card shows the current operation lifecycle.
- Successful completion updates the relevant card from newly collected fleet
  evidence.
- The page may wait only for the active foreground request. It contains no
  general polling loop.
- Reloading the page restores the latest fleet snapshot and bounded operation
  receipt.

## Fixed targets and dependency disclosure

```text
Maven   192.168.124.238  local reviewed A2/A3 services
Forge   192.168.124.225  SSH alias proxmox-maintenance
Pi-hole 192.168.124.206  SSH alias pihole-maintenance
```

Forge reboot impact includes Pi-hole LXC `100`. The UI must disclose this
before authorization. No request parameter may supply a host, address, SSH
alias, executable path, or command vector.

## Lifecycle

```text
previewed
→ authorized
→ maintaining / reboot_requested
→ waiting_for_reconnect
→ verifying
→ complete / failed / canceled / blocked_for_human_review
```

Every invocation terminates. The timer collector has only:

```text
collecting → complete / failed
```

## Explicitly prohibited

- Fleet-wide maintenance or fleet-wide reboot.
- Selecting or authorizing more than one device per request.
- Request-supplied targets or command arguments.
- Shell, `eval`, or model-generated command vectors.
- Passwords in Dashboard, Chat, Voice, files, arguments, or environment.
- Reusable sudo authorization or new NOPASSWD rules.
- Automatic reboot after maintenance.
- Automatic maintenance or reboot retry.
- Guest start, stop, migration, snapshot, restore, or deletion.
- Package autoremove, cache cleanup, orphan removal, downgrade, or unattended
  conflict resolution.
- A persistent worker, daemon, watcher, socket, or unbounded reconnect loop.
- A timer capable of mutation.
- Enabling live device mutation before human review of the C1 candidate.

## Deterministic acceptance

Tests must prove:

- target IDs are allowlisted and map to fixed adapters;
- preview and execute bind one device, action, revision, and digest;
- wrong device, stale digest, replay, concurrent operation, and wrong
  confirmation fail before mutation;
- a live lock owner blocks mutation, while dead-owner and old malformed locks
  are quarantined once without bypassing the acquisition-race grace period;
- lock release cannot remove a replacement lock created at the same path;
- Forge reboot visibly reports Pi-hole impact;
- Maven still delegates to A2/A3 and cannot bypass their gates;
- remote commands are fixed, shell-free, bounded, and never use user-provided
  target data;
- maintenance never reboots;
- reboot sends at most one reboot request and uses bounded reconnect checks;
- successful operations recollect and persist status;
- failed operations retain the previous snapshot and a redacted receipt;
- the cache is private, atomic, bounded, and symlink-safe;
- the timer has only noon/midnight calendar triggers and invokes only the
  one-shot status collector;
- no fleet-wide action exists; and
- legacy maintenance regressions continue to pass.

## Human acceptance

1. Review this brief.
2. Review the candidate code, fixed command vectors, units, tests, and review
   artifact.
3. Review the redesigned cards with live read-only evidence.
4. Install only the status timer through its exact plan/confirmation flow.
5. Run one supervised maintenance transaction against one selected device.
6. Review its receipt and refreshed card before authorizing another device.
7. Run one supervised reboot against one selected device only after reviewing
   its dependency impact and recovery expectations.
