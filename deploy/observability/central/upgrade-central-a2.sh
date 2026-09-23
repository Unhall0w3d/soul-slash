#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "upgrade-central-a2.sh must run as root" >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TARGETS_FILE=${1:-}
SNMP_FILE=${2:-}
LINUX_HOST_TARGETS_FILE=${3:-}

if [[ -n ${TARGETS_FILE} || -n ${SNMP_FILE} ]]; then
  [[ -n ${LINUX_HOST_TARGETS_FILE} ]] || { echo "SNMP replacement requires the rendered Linux host targets too; supply all three renderer outputs to preserve host monitoring" >&2; exit 1; }
  [[ -n ${TARGETS_FILE} && -n ${SNMP_FILE} ]] || { echo "switch targets and SNMP auth must be supplied together" >&2; exit 1; }
  for file in "${TARGETS_FILE}" "${SNMP_FILE}"; do
    [[ -f ${file} && ! -L ${file} ]] || { echo "owner-private SNMP input is unavailable" >&2; exit 1; }
    [[ $(stat -c '%a' "${file}") == 600 ]] || { echo "owner-private SNMP inputs must be mode 0600" >&2; exit 1; }
  done
fi
if [[ -n ${LINUX_HOST_TARGETS_FILE} ]]; then
  [[ -n ${SNMP_FILE} ]] || { echo "Linux host targets require the combined SNMP auth/module file" >&2; exit 1; }
  [[ -f ${LINUX_HOST_TARGETS_FILE} && ! -L ${LINUX_HOST_TARGETS_FILE} ]] || { echo "owner-private Linux host SNMP targets are unavailable" >&2; exit 1; }
  [[ $(stat -c '%a' "${LINUX_HOST_TARGETS_FILE}") == 600 ]] || { echo "owner-private Linux host SNMP targets must be mode 0600" >&2; exit 1; }
fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends prometheus-snmp-exporter

install -d -m 0755 /etc/systemd/system/prometheus-snmp-exporter.service.d
cat > /etc/systemd/system/prometheus-snmp-exporter.service.d/soul-observability.conf <<'EOF'
[Service]
# Debian's packaged unit enables PrivateUsers, which cannot create its user
# namespace inside the reviewed unprivileged LXC. Preserve every other package
# hardening directive and disable only the incompatible namespace feature.
PrivateUsers=false
ExecStart=
ExecStart=/usr/bin/prometheus-snmp-exporter --config.file=/etc/prometheus/snmp.yml --web.listen-address=127.0.0.1:9116
EOF

install -o root -g prometheus -m 0640 "${SCRIPT_DIR}/prometheus.yml" /etc/prometheus/prometheus.yml
install -d -o root -g prometheus -m 0750 /etc/prometheus/rules
install -o root -g prometheus -m 0640 "${SCRIPT_DIR}/fleet-alerts.yml" /etc/prometheus/rules/soul-fleet-alerts.yml
install -o root -g grafana -m 0640 "${SCRIPT_DIR}/fleet-operations.json" /var/lib/grafana/dashboards/fleet-operations.json

if [[ -n ${TARGETS_FILE} ]]; then
  install -o root -g prometheus -m 0640 "${TARGETS_FILE}" /etc/prometheus/soul-switch-targets.json
  install -o root -g prometheus -m 0640 "${SNMP_FILE}" /etc/prometheus/snmp.yml
elif [[ ! -f /etc/prometheus/soul-switch-targets.json ]]; then
  printf '%s\n' '[]' > /etc/prometheus/soul-switch-targets.json
  chown root:prometheus /etc/prometheus/soul-switch-targets.json
  chmod 0640 /etc/prometheus/soul-switch-targets.json
fi
if [[ -n ${LINUX_HOST_TARGETS_FILE} ]]; then
  install -o root -g prometheus -m 0640 "${LINUX_HOST_TARGETS_FILE}" /etc/prometheus/soul-linux-snmp-targets.json
elif [[ ! -f /etc/prometheus/soul-linux-snmp-targets.json ]]; then
  printf '%s\n' '[]' > /etc/prometheus/soul-linux-snmp-targets.json
  chown root:prometheus /etc/prometheus/soul-linux-snmp-targets.json
  chmod 0640 /etc/prometheus/soul-linux-snmp-targets.json
fi

/usr/bin/promtool check rules /etc/prometheus/rules/soul-fleet-alerts.yml
/usr/bin/promtool check config /etc/prometheus/prometheus.yml
systemctl daemon-reload
systemctl enable prometheus-snmp-exporter
systemctl restart prometheus-snmp-exporter prometheus grafana-server
for unit in prometheus-snmp-exporter prometheus grafana-server; do systemctl is-active --quiet "${unit}"; done

install -d -m 0700 /var/lib/soul-observability
printf '%s\n' '{"schema_version":"soul.fleet-observability.central-upgrade.a2.v1","alerts":"dashboard_only","snmp":"owner_private_optional","mutation_authority":"none"}' \
  > /var/lib/soul-observability/a2-receipt.json
chmod 0600 /var/lib/soul-observability/a2-receipt.json
echo "Fleet Observability A2 central upgrade completed; switch evidence remains absent unless owner-private SNMP inputs were supplied."
