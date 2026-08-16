#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "upgrade-collector-a2.sh must run as root" >&2
  exit 1
fi

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
[[ -f /etc/soul-observability/collector.env ]] || { echo "existing collector identity is unavailable" >&2; exit 1; }
[[ -f /etc/soul-observability/ingest-password ]] || { echo "existing collector credential is unavailable" >&2; exit 1; }
[[ -f /etc/soul-observability/ca.crt ]] || { echo "existing Observatory CA is unavailable" >&2; exit 1; }

getent group systemd-journal >/dev/null && usermod -a -G systemd-journal alloy
install -o root -g alloy -m 0640 "${SCRIPT_DIR}/config.alloy" /etc/soul-observability/config.alloy
/usr/local/bin/alloy validate /etc/soul-observability/config.alloy
systemctl restart alloy
systemctl is-active --quiet alloy
echo "Fleet Observability A2 collector upgrade completed with redacted maintenance-unit lifecycle evidence."
