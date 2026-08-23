#!/usr/bin/bash
set -euo pipefail

helper="scripts/soul-e1000e-recovery"
unit="config/systemd/soul-e1000e-recovery.service"
brief="docs/soul/E1000E_HARDWARE_HANG_RECOVERY_A0_BRIEF.md"

for path in "$helper" "$unit" "$brief"; do
  [[ -f "$path" ]] || { printf 'missing %s\n' "$path" >&2; exit 1; }
done

/usr/bin/bash -n "$helper"
/usr/bin/grep -Fq 'readonly INTERFACE="nic0"' "$helper"
/usr/bin/grep -Fq 'readonly DRIVER="e1000e"' "$helper"
/usr/bin/grep -Fq 'readonly EVENT="e1000e 0000:00:1f.6 nic0: Detected Hardware Unit Hang:"' "$helper"
/usr/bin/grep -Fq 'readonly COOLDOWN_SECONDS=60' "$helper"
/usr/bin/grep -Fq '/usr/sbin/ip link set dev "$INTERFACE" down' "$helper"
/usr/bin/grep -Fq '/usr/sbin/ip link set dev "$INTERFACE" up' "$helper"
/usr/bin/grep -Fq 'journalctl --dmesg --follow --lines=0 --output=cat' "$helper"
/usr/bin/grep -Fq 'CapabilityBoundingSet=CAP_NET_ADMIN' "$unit"
/usr/bin/grep -Fq 'Restart=on-failure' "$unit"
/usr/bin/grep -Fq 'StartLimitBurst=5' "$unit"
/usr/bin/grep -Fq 'UMask=0077' "$unit"

if /usr/bin/grep -Eq '(eval|bash -c|sh -c|\$\{[^}]*:-nic0\}|INTERFACE=\$)' "$helper"; then
  printf '%s\n' 'dynamic command or target construction detected' >&2
  exit 1
fi

printf '%s\n' 'e1000e hardware-hang recovery A0 verification passed'
