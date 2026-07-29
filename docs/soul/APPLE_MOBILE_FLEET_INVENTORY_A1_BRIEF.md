# Apple Mobile Fleet Inventory A1 Brief

```text
date: 2026-07-28
human_authorization: approved in the active development conversation
implementation_authorized: yes
risk: Class 2 local USB and private-network inventory
```

## Objective

Enrich an enrolled, DHCP-tracked Apple mobile device with a small,
privacy-preserving inventory projection when the same reviewed device is
connected and trusted over USB. Preserve ordinary LAN reachability and DHCP
identity as the normal fleet-status path.

## Approved adapter

The adapter may:

- check for the fixed `idevice_id` and `ideviceinfo` executables;
- list at most four locally attached USB device identifiers;
- use each identifier ephemerally to query one allowlisted identity projection;
- match the connected device to an enrolled record only by the record's exact,
  previously reviewed Wi-Fi MAC address;
- record `apple_mobile` as that private registry record's inventory adapter
  after the first exact trusted-USB and reviewed-MAC match;
- query one battery projection only after that exact match;
- expose device name, product type, iOS version, build, architecture, battery
  percentage, charging, external-power, and fully-charged state;
- run during an explicit device refresh or existing bounded fleet collection;
- retain only the allowlisted projection in the private fleet-status snapshot.

## Privacy boundary

The adapter must not return, log, or persist:

- UDID or pairing-record filenames;
- serial number, IMEI, MEID, phone number, ICCID, eSIM, or carrier identity;
- Apple ID, account, application, file, message, call, photo, backup, diagnostic,
  or location data;
- raw `ideviceinfo` output;
- pairing certificates, host IDs, system BUIDs, or private keys.

The ephemeral USB identifier may appear only as an argument to a fixed local
command while the foreground operation is active.

## Matching and lifecycle

1. Preserve the existing bounded LAN reachability and reviewed-MAC check.
2. Skip enrichment unless the enrolled record is `status_only`,
   `dhcp_tracked`, and has one valid reviewed MAC.
3. List at most four USB devices through fixed `idevice_id -l`.
4. Query only the Wi-Fi address and allowlisted identity keys for each device,
   stopping at the first exact reviewed-MAC match.
5. Query the allowlisted battery domain for that match.
6. Return `available`, `dependency_unavailable`, `not_connected`,
   `locked_or_untrusted`, or `no_reviewed_match`.
7. Terminate every invoked command and the parent operation. No process waits
   for connection, unlock, trust, or user input.

Before the first exact match, unrelated DHCP-tracked devices receive no Apple
classification. After an exact match binds the adapter, an absent cable or
locked phone does not make the LAN device offline and does not erase the last
independently reviewed identity. It reports only that deep inventory was
unavailable for the current observation.

## Bounds

- Maximum attached devices inspected: 4.
- Maximum per command: 5 seconds.
- Maximum captured output per command: 64 KiB.
- Commands are fixed, shell-free, and read-only.
- No retry, watcher, listener, service, daemon, timer, or background process.
- No phone setting, pairing, sync, backup, restore, application, or file
  mutation.
- No network `netmuxd` dependency. A future network adapter requires separate
  evidence and review.

## Public/local boundary

Tracked source contains the generic adapter, allowlists, deterministic
fixtures, documentation, and Dashboard presentation. Device addresses, MACs,
identifiers, facts, pairing records, and fleet snapshots remain owner-private
ignored state.

## Acceptance

- A matching connected and trusted fixture produces only the allowlisted
  projection.
- A nonmatching phone never enriches another fleet record.
- More than four attached identifiers are ignored.
- Missing dependencies, timeout, locked phone, absent cable, malformed output,
  and failed battery query terminate safely.
- UDID, serial, IMEI, phone identity, and raw output are absent from returned
  and persisted data.
- LAN status remains truthful when wired inventory is unavailable.
- Dashboard status-only cards show the bounded Apple projection when available
  and a concise current-observation reason otherwise.
