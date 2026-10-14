#!/usr/bin/env bash
# Read-only host diagnostics; writes only a new private directory under /tmp.
set -uo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin LC_ALL=C SYSTEMD_PAGER=cat PAGER=cat
umask 077

usage() {
  printf '%s\n' 'Usage: bash collect-pve-lockup.sh [--date YYYY-MM-DD] [--since TIME --until TIME] [--include-config]' \
    'Default: today 02:00 through 07:00 in the HOST timezone, plus recent/previous-boot evidence.' \
    'Run as root on the affected PVE host after recovery. No installs, repairs or active disk tests.' \
    '--include-config adds bounded scheduler/storage/cron configuration; may contain secrets.' \
    'All bundles contain private host/log metadata. Review before sharing; not auto-redacted.'
}
day=$(date +%F); since=''; until=''; configs=0
while (($#)); do
  case "$1" in
    --date|--since|--until)
      (($# >= 2)) || { usage >&2; exit 2; }
      case "$1" in --date) day=$2;; --since) since=$2;; --until) until=$2;; esac
      shift 2 ;;
    --include-config) configs=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) usage >&2; exit 2 ;;
  esac
done
[[ $day =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] && date -d "$day" >/dev/null 2>&1 || { echo 'Invalid date' >&2; exit 2; }
since=${since:-"$day 02:00:00"}; until=${until:-"$day 07:00:00"}
start_epoch=$(date -d "$since" +%s) && end_epoch=$(date -d "$until" +%s) || exit 2
((end_epoch > start_epoch && end_epoch-start_epoch <= 7*86400)) || { echo 'Window must be positive and at most seven days.' >&2; exit 2; }
((EUID == 0)) || { echo 'Run from the Proxmox root shell (or sudo bash ...).' >&2; exit 1; }
command -v pveversion >/dev/null || { echo 'This is not a detected Proxmox VE host.' >&2; exit 1; }
for cmd in timeout head tail tar sha256sum stat find date df awk; do
  command -v "$cmd" >/dev/null || { echo "Required command missing: $cmd" >&2; exit 1; }
done
available=$(df -B1 --output=avail /tmp | tail -n 1)
[[ $available =~ ^[[:space:]]*[0-9]+$ ]] && ((available >= 268435456)) || { echo 'Need at least 256 MiB free in /tmp.' >&2; exit 1; }
work=$(mktemp -d /tmp/pve-lockup-XXXXXXXX) || exit 1
mkdir "$work/evidence" || exit 1
SECONDS=0; count=0; total=0
limit=1048576; budget=67108864
printf 'Private collection: %s\n' "$work"
printf 'label\texit\tbytes\tcap_reached\tcommand\n' > "$work/commands.tsv"
trap 'printf "Interrupted; partial evidence retained at %s\n" "$work" >&2; exit 130' INT TERM

collect() {
  local label=$1 rc bytes cap quoted allowance
  shift
  if ((SECONDS >= 300 || total >= budget || count >= 160)); then
    printf '%s\tSKIPPED_BUDGET\n' "$label" >> "$work/commands.tsv"; return
  fi
  if ! command -v "$1" >/dev/null 2>&1; then
    printf '%s\tMISSING_TOOL\t%s\n' "$label" "$1" >> "$work/commands.tsv"; return
  fi
  allowance=$((300-SECONDS)); ((allowance > 15)) && allowance=15
  printf -v quoted '%q ' "$@"
  timeout --signal=TERM --kill-after=2s "${allowance}s" "$@" 2>&1 | head -c "$limit" > "$work/evidence/$label.txt"
  rc=${PIPESTATUS[0]}
  bytes=$(stat -c %s "$work/evidence/$label.txt")
  cap=no; ((bytes >= limit)) && cap=yes
  printf '%s\t%s\t%s\t%s\t%s\n' "$label" "$rc" "$bytes" "$cap" "$quoted" >> "$work/commands.tsv"
  total=$((total+bytes)); count=$((count+1))
}
read_file() {
  local label=$1 file=$2
  if [[ -f $file && ! -L $file ]]; then
    collect "${label}-metadata" stat --printf='%n size=%s modified=%y mode=%a\n' -- "$file"
    collect "$label" tail -c "$limit" -- "$file"
  fi
}
printf 'Collected UTC: %s\nWindow host time: %s through %s\nEpoch window: %s through %s\nInclude configuration: %s\n' \
  "$(date -u --iso-8601=seconds)" "$since" "$until" "$start_epoch" "$end_epoch" "$configs" > "$work/README.txt"
printf '%s\n' \
  'PRIVATE: logs can include IPs, usernames, paths, VM names and accidental secrets. No automatic redaction.' \
  'No VM disks, guest files, keys, /etc/pve/priv, environment dumps, raw core dumps or full pvereport included.' \
  'commands.tsv records missing tools, exit codes and output caps. 124/137 may indicate timeout, not a root cause.' \
  'Journal output is newest-first; each output capped at 1 MiB. File excerpts retain the tail.' \
  'Collection budget: 5 minutes between commands, at most 160 commands / 64 MiB. Packaging adds time.' \
  'Kernel uninterruptible I/O cannot reliably be killed by timeout. Run after the host has recovered.' \
  'Absent previous-boot/pstore evidence does not establish a clean shutdown. No monitoring is enabled.' \
  'Current telemetry after reboot is not historical telemetry from the incident.' \
  'No SMART self-test, scrub, trim, benchmark, filesystem check, reboot or network probe is performed.' >> "$work/README.txt"

# Capture volatile/high-value evidence before lower-priority inventory.
collect clock date --iso-8601=seconds
collect timezone timedatectl
collect uptime uptime
collect boot-id cat /proc/sys/kernel/random/boot_id
collect version pveversion -v
collect kernel uname -a
collect os-release cat /etc/os-release
collect cmdline cat /proc/cmdline
collect boots journalctl --list-boots --no-pager
collect incident journalctl --since "$since" --until "$until" -r -n 30000 -o short-iso-precise --no-pager
collect incident-kernel journalctl -k --since "$since" --until "$until" -b all -r -n 15000 -o short-iso-precise --no-pager
collect previous-boot journalctl -b -1 -r -n 15000 -o short-iso-precise --no-pager
collect previous-kernel journalctl -b -1 -k -r -n 15000 -o short-iso-precise --no-pager
collect current-kernel journalctl -b 0 -k -r -n 15000 -o short-iso-precise --no-pager
collect recent-warnings journalctl --since '3 days ago' -p warning -r -n 10000 -o short-iso-precise --no-pager
collect dmesg dmesg --time-format iso
collect journal-storage journalctl --disk-usage
collect journal-policy systemd-analyze cat-config systemd/journald.conf
collect shutdown-history last -x -n 40
collect core-index coredumpctl --no-pager --since "$since" --until "$until" list
collect pstore-service systemctl status systemd-pstore.service --no-pager -l
for dir in /sys/fs/pstore /var/lib/systemd/pstore; do
  if [[ -d $dir ]]; then
    index=0
    while IFS= read -r -d '' file; do
      read_file "pstore-${dir//\//_}-$index" "$file"
      index=$((index+1)); ((index >= 12)) && break
    done < <(timeout --kill-after=2s 5s find "$dir" -maxdepth 1 -type f -print0)
  fi
done
collect watchdog-policy sysctl kernel.watchdog kernel.nmi_watchdog kernel.watchdog_thresh kernel.softlockup_panic kernel.hardlockup_panic kernel.hung_task_timeout_secs kernel.hung_task_panic kernel.panic kernel.panic_on_oops vm.panic_on_oom
collect memory free -h
collect meminfo cat /proc/meminfo
collect pressure cat /proc/pressure/cpu /proc/pressure/memory /proc/pressure/io
collect processes ps -eo pid,ppid,stat,comm,wchan:32,%cpu,%mem --sort=-%cpu
collect vmstat vmstat 1 5
collect timers systemctl list-timers --all --no-pager
collect failed-units systemctl --failed --no-pager
collect pve-units systemctl status pve-cluster pvedaemon pveproxy pvestatd pvescheduler pve-ha-lrm pve-ha-crm corosync watchdog-mux --no-pager -l
collect pve-events journalctl --since "$since" --until "$until" -r -n 15000 --no-pager -o short-iso-precise -u pvescheduler -u pvedaemon -u pvestatd -u pveproxy -u pve-cluster -u corosync -u pve-ha-lrm -u pve-ha-crm -u watchdog-mux -u cron -u fstrim -u apt-daily -u apt-daily-upgrade
collect cluster pvecm status
collect ha ha-manager status
collect task-list pvenode task list --limit 100
collect guests-qemu qm list
collect guests-lxc pct list
collect replication pvesr status
collect local-filesystems df -hT -l
collect local-inodes df -i -l
collect mounts findmnt -rn -o TARGET,SOURCE,FSTYPE
collect disks lsblk -e 7 -o NAME,TYPE,SIZE,FSTYPE,MOUNTPOINTS,MODEL,REV,ROTA
index=0
while read -r device kind; do
  [[ $kind == disk && $device == /dev/* && -b $device ]] || continue
  collect "disk-health-$index" smartctl -n standby -x "$device"
  index=$((index+1)); ((index >= 8)) && break
done < <(timeout --kill-after=2s 5s lsblk -dnpo NAME,TYPE)
collect mdstat cat /proc/mdstat
collect zpool-health zpool status -v
collect zpool-capacity zpool list
collect zpool-events zpool events -v
collect zfs-memory head -n 100 /proc/spl/kstat/zfs/arcstats
collect lvm pvs --readonly
collect lvm-volumes lvs --readonly -a -o lv_name,vg_name,lv_size,lv_attr,data_percent,metadata_percent
collect interfaces ip -s link
index=0
for device in /sys/class/net/*; do
  [[ -e $device/device ]] || continue
  collect "nic-driver-$index" ethtool -i "${device##*/}"
  collect "nic-statistics-$index" ethtool -S "${device##*/}"
  index=$((index+1)); ((index >= 8)) && break
done
collect addresses ip -brief address
collect routes ip route show
collect sockets ss -s
collect pci lspci -nnk
collect cpu lscpu
collect bios dmidecode -t bios
collect temperatures sensors
collect bmc-events ipmitool sel elist
collect bmc-sensors ipmitool sdr elist
collect ras ras-mc-ctl --errors
collect time-sync chronyc tracking
read_file dpkg-history /var/log/dpkg.log
read_file apt-history /var/log/apt/history.log
read_file apt-history-rotated /var/log/apt/history.log.1
collect installed-kernels dpkg-query -W 'proxmox-kernel*' 'pve-kernel*' 'intel-microcode' 'amd64-microcode'
collect journal-directories ls -ld /var/log/journal /run/log/journal /var/crash /sys/fs/pstore /var/lib/systemd/pstore
index=0
for file in "/var/log/sysstat/sa${day##*-}" "/var/log/sysstat/sa${day//-/}" "/var/log/sa/sa${day##*-}"; do
  [[ -f $file && ! -L $file ]] || continue
  collect "historical-sar-$index" sar -A -f "$file"
  index=$((index+1))
done

# Prefer existing text task logs; never traverse guests or full backup storage.
index=0
if [[ -d /var/log/pve/tasks ]]; then
  while IFS= read -r -d '' file; do
    read_file "pve-task-$index" "$file"
    index=$((index+1)); ((index >= 24)) && break
  done < <(timeout --kill-after=2s 5s find /var/log/pve/tasks -maxdepth 2 -type f -newermt "$since" ! -newermt "$until" -name 'UPID:*' -print0)
fi
printf 'Task file excerpts: %s (max 24, modification-time selection; may omit overlapping/older tasks).\n' "$index" >> "$work/README.txt"
if ((configs)); then
  index=0
  for file in /etc/pve/jobs.cfg /etc/pve/replication.cfg /etc/pve/storage.cfg /etc/vzdump.conf /etc/crontab /etc/anacrontab /etc/cron.d/* /var/spool/cron/crontabs/root; do
    read_file "schedule-config-$index" "$file"
    index=$((index+1)); ((index >= 30)) && break
  done
fi
printf 'Collection seconds: %s\nCaptured commands: %s\nCaptured output bytes: %s\n' "$SECONDS" "$count" "$total" >> "$work/README.txt"
(cd "$work" && sha256sum README.txt commands.tsv evidence/*.txt > SHA256SUMS) || exit 1
archive="$work/$(basename "$work").tar"
timeout --kill-after=5s 60s tar -C "$work" -cf "$archive" README.txt commands.tsv SHA256SUMS evidence || { echo "Packaging failed; evidence retained: $work" >&2; exit 1; }
chmod 600 "$archive"
sha256sum "$archive" > "$archive.sha256"
printf '\nArchive: %s\nChecksum: %s.sha256\nPrivate working files retained beside archive; no automatic deletion.\n' "$archive" "$archive"
