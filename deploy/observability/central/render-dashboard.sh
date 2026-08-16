#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "render-dashboard.sh must run as root" >&2
  exit 1
fi

ENV_FILE=${1:-/root/soul-observability-site.env}
TARGET=${2:-/var/lib/grafana/dashboards/fleet-overview.json}
[[ -f ${ENV_FILE} ]] || { echo "missing owner-private site environment file" >&2; exit 1; }
[[ $(stat -c '%a' "${ENV_FILE}") == 600 ]] || { echo "site environment file must be mode 0600" >&2; exit 1; }
# shellcheck disable=SC1090
source "${ENV_FILE}"
: "${SITE_LABEL:?missing SITE_LABEL}"
: "${SITE_LATITUDE:?missing SITE_LATITUDE}"
: "${SITE_LONGITUDE:?missing SITE_LONGITUDE}"

[[ ${SITE_LABEL} =~ ^[A-Za-z0-9._\ -]{1,64}$ ]] || { echo "SITE_LABEL is invalid" >&2; exit 1; }
[[ ${SITE_LATITUDE} =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { echo "SITE_LATITUDE is invalid" >&2; exit 1; }
[[ ${SITE_LONGITUDE} =~ ^-?[0-9]+([.][0-9]+)?$ ]] || { echo "SITE_LONGITUDE is invalid" >&2; exit 1; }
awk -v value="${SITE_LATITUDE}" 'BEGIN { exit !(value >= -90 && value <= 90) }' || { echo "SITE_LATITUDE is out of range" >&2; exit 1; }
awk -v value="${SITE_LONGITUDE}" 'BEGIN { exit !(value >= -180 && value <= 180) }' || { echo "SITE_LONGITUDE is out of range" >&2; exit 1; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
tmp=$(mktemp)
trap 'rm -f "${tmp}"' EXIT
escaped_label=${SITE_LABEL//\\/\\\\}
escaped_label=${escaped_label//&/\\&}
escaped_label=${escaped_label//|/\\|}
sed \
  -e "s|__SOUL_SITE_LABEL__|${escaped_label}|g" \
  -e "s|__SOUL_SITE_LATITUDE__|${SITE_LATITUDE}|g" \
  -e "s|__SOUL_SITE_LONGITUDE__|${SITE_LONGITUDE}|g" \
  "${SCRIPT_DIR}/fleet-overview.json" > "${tmp}"

if grep -q '__SOUL_SITE_' "${tmp}"; then
  echo "dashboard contains unresolved owner-local placeholders" >&2
  exit 1
fi

install -o grafana -g grafana -m 0640 "${tmp}" "${TARGET}"
echo "rendered owner-local dashboard without modifying the public template"
