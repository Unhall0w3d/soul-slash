# Apple Mobile Fleet Inventory A1 Review

## Candidate summary

Adds one optional, read-only Apple mobile inventory adapter to Guided
Maintenance. An enrolled DHCP-tracked record is classified as `apple_mobile`
only after an unlocked, trusted USB device reports the same exact per-network
private Wi-Fi MAC that the Operator previously reviewed during enrollment.

Ordinary LAN reachability and DHCP retargeting remain authoritative. A missing
cable, locked phone, unavailable dependency, or failed inventory query never
makes an otherwise reachable phone offline and never grants mutation authority.

## Files changed

- `lib/soul_core/apple_mobile_inventory_adapter.rb`
- `lib/soul_core/maintenance_fleet_status_service.rb`
- `lib/soul_core/maintenance_fleet_discovery_service.rb`
- `assets/dashboard/dashboard.js`
- `assets/dashboard/dashboard.css`
- `scripts/verify-maintenance-fleet-status-b1.rb`
- `scripts/verify-apple-mobile-fleet-inventory-a1.rb`
- `Makefile`
- `docs/soul/APPLE_MOBILE_FLEET_INVENTORY_A1_BRIEF.md`
- `docs/guides/GUIDED_MAINTENANCE.md`
- `docs/CURRENT_STATE.md`
- `docs/assessments/APPLE_MOBILE_FLEET_INVENTORY_A1_REVIEW.md`

## Command and lifecycle contract

The adapter uses only:

```text
/usr/bin/idevice_id -l
/usr/bin/ideviceinfo -u <ephemeral USB identifier> -q com.apple.mobile.wireless_lockdown -k InstanceName
/usr/bin/ideviceinfo -u <ephemeral USB identifier> -k <allowlisted identity key>
/usr/bin/ideviceinfo -u <ephemeral USB identifier> -q com.apple.mobile.battery
```

Every command is shell-free, capped at three seconds and 64 KiB, and runs only
inside the existing foreground fleet collection or selected-device refresh.
At most four attached USB identifiers are inspected. There is no retry,
listener, daemon, watcher, timer, or process after the operation returns.

Terminal adapter states:

- `available`
- `dependency_unavailable`
- `dependency_failed`
- `timeout`
- `not_connected`
- `locked_or_untrusted`
- `no_reviewed_match`
- `not_applicable`

## Privacy review

Returned and persisted fields are limited to:

- device name;
- Apple product type;
- iOS version and build;
- CPU architecture;
- battery percentage;
- charging, external-power, and fully-charged booleans;
- adapter state and reviewed-match semantics.

The adapter does not return, log, or persist UDID, serial, IMEI, MEID, phone
number, ICCID/eSIM, account, carrier, application, file, backup, diagnostic,
location, pairing certificate, host ID, system BUID, private key, or raw command
output.

The per-network private Wi-Fi MAC was already approved for DHCP identity and
remains owner-private. The first exact match adds only
`inventory_adapter: apple_mobile` to that private registry record.

## Deterministic verification

Commands:

```text
ruby -c lib/soul_core/apple_mobile_inventory_adapter.rb
ruby -c lib/soul_core/maintenance_fleet_status_service.rb
ruby -c lib/soul_core/maintenance_fleet_discovery_service.rb
node --check assets/dashboard/dashboard.js
make apple-mobile-inventory-check
make verify-apple-mobile-fleet-inventory
make verify-maintenance-fleet-status
make verify-maintenance-fleet-discovery
make verify-maintenance-fleet-dhcp-identity
```

Results:

- exact reviewed private-MAC match: PASS
- allowlisted projection only: PASS
- ephemeral identifier and sensitive-field exclusion: PASS
- fixed bounded shell-free command vectors: PASS
- nonmatching-device isolation: PASS
- locked/untrusted terminal state: PASS
- four-device inspection bound: PASS
- dependency-unavailable handling: PASS
- exact-match private adapter binding: PASS
- disconnected bound-device state: PASS
- existing fleet-status regression suite: PASS
- SSH-integrated-before-status-only Dashboard ordering: PASS
- existing portable-discovery regression suite: PASS
- existing DHCP-identity regression suite: PASS

## Live evidence

On Maven:

- `usbmuxd 1.1.1` and `libimobiledevice 1.4.0` detected;
- data-capable USB cable and iPhone trust accepted;
- pairing validation succeeded after one explicit `usbmuxd` restart;
- wired allowlisted identity and battery queries succeeded;
- the wireless-lockdown current-network identity exactly matched the reviewed
  private MAC in the enrolled reviewed-iPhone fixture;
- iPhone product type, iOS/build, architecture, and charging projection were
  returned without querying applications, files, accounts, or backups.
- after the Operator updated the reviewed phone to iOS 27 public beta 2, one
  selected-device Dashboard refresh showed Online from LAN evidence alongside
  `APPLE INVENTORY · TRUSTED USB`, `iPhone16,2`, iOS `27.0` build `24A5390f`,
  and current charging evidence;
- after USB disconnection, a second selected-device Dashboard refresh preserved
  Online and active LAN reachability while changing the bounded projection to
  `APPLE INVENTORY · NOT CONNECTED`;
- the live Dashboard projection exposed no USB identifier, MAC address, serial,
  account, carrier, application, file, or backup data.

Network inventory was separately researched and rejected for this slice:

- `netmuxd-bin` v0.3.2 was checksum-verified and run only unprivileged,
  loopback-only, without the Unix socket;
- upstream v0.4.3 was locally built from its exact tag with `--locked`, run
  with USB and Unix-socket ownership disabled, and never installed;
- both versions reached the phone's sync endpoint but the paired lockdown
  session closed (`early eof` / `broken pipe`);
- all temporary listeners terminated, and no network adapter or daemon was
  introduced.

## Known weaknesses

- Apple product types remain Apple's stable machine identifiers rather than a
  hard-coded marketing-name table.
- Wired inventory requires the phone to be unlocked and already trusted at the
  instant of refresh.
- Network deep inventory is explicitly unsupported.
- Battery-domain failure retains identity evidence but may show unavailable
  battery values.

## Memory and persistence

- Shared Soul memory keys added: none.
- Skill-private memory: none.
- Private fleet registry: optional `inventory_adapter: apple_mobile` on one
  exact reviewed record.
- Private fleet snapshot: current allowlisted projection only.
- Temporary build and diagnostic files: `/tmp` only; not part of Soul state.

## Risk classification

Class 2 local USB read plus Class 2 owner-private adapter-classification
mutation. Device mutation, pairing, sync, backup, restore, firmware, account,
file, application, and remote control authority remain absent.

## Human review checklist

- [x] Update the reviewed iPhone and reconnect it with a data-capable cable.
- [x] Keep the phone unlocked and confirm existing trust remains valid.
- [x] Refresh only the reviewed iPhone card.
- [x] Confirm Online remains based on LAN evidence.
- [x] Confirm Apple inventory shows trusted USB, product/iOS, and battery.
- [x] Disconnect the cable and refresh again.
- [x] Confirm LAN status remains truthful and wired inventory reports
      unavailable.
- [x] Confirm no Maintenance or Reboot control appears.
- [ ] Approve or reject the candidate before merge.
