#!/usr/bin/env bash
set -euo pipefail
[[ ${EUID} -eq 0 ]] || { echo 'run as root' >&2; exit 1; }
source_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
state_root=/var/lib/soul-network-syslog
rollback_dir="$state_root/rollback-$(date -u +%Y%m%dT%H%M%SZ)"
rsyslog_target=/etc/rsyslog.d/10-soul-network-devices.conf
logrotate_target=/etc/logrotate.d/soul-network-devices
status_target=/usr/local/libexec/soul-network-syslog-status
wazuh_target=/var/ossec/etc/ossec.conf
zone=
installed=0
for file in 10-soul-network-devices.conf soul-network-devices.logrotate soul-network-syslog-status wazuh-localfile.xml; do
  [[ -f "$source_dir/$file" && ! -L "$source_dir/$file" ]] || { echo "missing candidate: $file" >&2; exit 1; }
done
ip -4 addr show dev eth0 | grep -Fq '192.168.124.2/24' || { echo 'Crucible private identity mismatch' >&2; exit 1; }
[[ -f "$wazuh_target" && ! -L "$wazuh_target" ]] || { echo 'Wazuh agent configuration unavailable' >&2; exit 1; }
install -d -m 0700 "$rollback_dir"
for target in "$rsyslog_target" "$logrotate_target" "$status_target" "$wazuh_target"; do
  if [[ -e "$target" ]]; then cp -a -- "$target" "$rollback_dir/$(basename -- "$target").before"; fi
done
rollback() {
  local exit_code=$?
  (( exit_code == 0 || installed == 0 )) && return
  systemctl disable --now rsyslog.service >/dev/null 2>&1 || true
  for target in "$rsyslog_target" "$logrotate_target" "$status_target"; do
    backup="$rollback_dir/$(basename -- "$target").before"
    if [[ -e "$backup" ]]; then cp -a -- "$backup" "$target"; else rm -f -- "$target"; fi
  done
  cp -a -- "$rollback_dir/$(basename -- "$wazuh_target").before" "$wazuh_target"
  if [[ -n "$zone" ]]; then
    for source in 192.168.124.10 192.168.124.11; do
      firewall-cmd --quiet --zone="$zone" --permanent --remove-rich-rule="rule family=ipv4 source address=$source port port=514 protocol=udp accept" || true
    done
    firewall-cmd --quiet --reload || true
  fi
  systemctl restart wazuh-agent.service >/dev/null 2>&1 || true
  echo "deployment rolled back; evidence retained at $rollback_dir" >&2
  exit "$exit_code"
}
trap rollback EXIT
dnf -y install rsyslog
installed=1
install -d -o root -g root -m 0750 /var/log/network-devices
install -o root -g root -m 0644 "$source_dir/10-soul-network-devices.conf" "$rsyslog_target"
install -o root -g root -m 0644 "$source_dir/soul-network-devices.logrotate" "$logrotate_target"
install -o root -g root -m 0755 "$source_dir/soul-network-syslog-status" "$status_target"
rsyslogd -N1
logrotate --debug "$logrotate_target" >/dev/null
if ! grep -Fq '<location>/var/log/network-devices/*.log</location>' "$wazuh_target"; then
  temporary=$(mktemp "$state_root/ossec.conf.XXXXXX")
  awk -v fragment="$source_dir/wazuh-localfile.xml" '
    /<\/ossec_config>/ && !inserted { while ((getline line < fragment) > 0) print line; close(fragment); inserted=1 }
    { print }
    END { if (!inserted) exit 42 }
  ' "$wazuh_target" >"$temporary"
  chown --reference="$wazuh_target" "$temporary"
  chmod --reference="$wazuh_target" "$temporary"
  mv -f -- "$temporary" "$wazuh_target"
fi
/var/ossec/bin/wazuh-logcollector -t
/var/ossec/bin/wazuh-agentd -t
zone=$(firewall-cmd --get-zone-of-interface=eth0)
[[ -n "$zone" && "$zone" != no\ zone ]] || { echo 'active firewalld zone unavailable' >&2; exit 1; }
for source in 192.168.124.10 192.168.124.11; do
  firewall-cmd --quiet --zone="$zone" --permanent --add-rich-rule="rule family=ipv4 source address=$source port port=514 protocol=udp accept"
done
firewall-cmd --quiet --reload
systemctl enable --now rsyslog.service
systemctl restart wazuh-agent.service
systemctl is-active --quiet wazuh-agent.service
"$status_target"
sha256sum "$rsyslog_target" "$logrotate_target" "$status_target" "$wazuh_target" >"$rollback_dir/deployed.sha256"
chmod 0600 "$rollback_dir/deployed.sha256"
trap - EXIT
printf 'Crucible network syslog receiver installed; rollback evidence: %s\n' "$rollback_dir"
