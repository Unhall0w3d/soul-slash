#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "install-collector.sh must run as root" >&2
  exit 1
fi

ENV_FILE=${1:-/root/soul-observability-collector.env}
CA_FILE=${2:-/root/soul-observability-ca.crt}
[[ -f ${ENV_FILE} && -f ${CA_FILE} ]] || { echo "missing owner-private environment or CA file" >&2; exit 1; }
[[ $(stat -c '%a' "${ENV_FILE}") == 600 ]] || { echo "environment file must be mode 0600" >&2; exit 1; }
# shellcheck disable=SC1090
set -a
source "${ENV_FILE}"
set +a
: "${OBSERVABILITY_URL:?missing OBSERVABILITY_URL}"
: "${OBSERVABILITY_PASSWORD:?missing OBSERVABILITY_PASSWORD}"
: "${SOUL_DEVICE_ID:?missing SOUL_DEVICE_ID}"
: "${SOUL_DEVICE_ROLE:?missing SOUL_DEVICE_ROLE}"
: "${SOUL_PLATFORM:?missing SOUL_PLATFORM}"
: "${SOUL_ENVIRONMENT:?missing SOUL_ENVIRONMENT}"
[[ ${OBSERVABILITY_URL} =~ ^https://[a-z0-9.-]+$ ]] || { echo "OBSERVABILITY_URL is invalid" >&2; exit 1; }
[[ ${OBSERVABILITY_PASSWORD} =~ ^[A-Za-z0-9]{32,128}$ ]] || { echo "ingest password must be 32-128 alphanumeric characters" >&2; exit 1; }
for value in "${SOUL_DEVICE_ID}" "${SOUL_DEVICE_ROLE}" "${SOUL_PLATFORM}" "${SOUL_ENVIRONMENT}"; do
  [[ ${value} =~ ^[a-z0-9_-]+$ ]] || { echo "collector identity labels must be lowercase bounded identifiers" >&2; exit 1; }
done
for command in curl unzip sha256sum getent useradd install systemctl; do
  command -v "${command}" >/dev/null || { echo "required command is unavailable: ${command}" >&2; exit 1; }
done

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ALLOY_VERSION=v1.18.1
ALLOY_ZIP_SHA256=fac853cbc3983a50a2368f9a685b31f74392ae86dd6155461b11a911c07b483c
tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT

curl -fsSL "https://github.com/grafana/alloy/releases/download/${ALLOY_VERSION}/alloy-linux-amd64.zip" -o "${tmpdir}/alloy.zip"
printf '%s  %s\n' "${ALLOY_ZIP_SHA256}" "${tmpdir}/alloy.zip" | sha256sum -c -
unzip -q "${tmpdir}/alloy.zip" -d "${tmpdir}"
install -m 0755 "${tmpdir}/alloy-linux-amd64" /usr/local/bin/alloy

getent group alloy >/dev/null || groupadd --system alloy
id alloy >/dev/null 2>&1 || useradd --system --gid alloy --home-dir /var/lib/alloy --shell /usr/sbin/nologin alloy
install -d -o root -g alloy -m 0750 /etc/soul-observability
install -d -o alloy -g alloy -m 0750 /var/lib/alloy
install -o root -g alloy -m 0640 "${SCRIPT_DIR}/config.alloy" /etc/soul-observability/config.alloy
install -o root -g alloy -m 0640 "${CA_FILE}" /etc/soul-observability/ca.crt
printf '%s' "${OBSERVABILITY_PASSWORD}" > /etc/soul-observability/ingest-password
chown root:alloy /etc/soul-observability/ingest-password
chmod 0640 /etc/soul-observability/ingest-password
cat > /etc/soul-observability/collector.env <<EOF
OBSERVABILITY_URL=${OBSERVABILITY_URL}
SOUL_DEVICE_ID=${SOUL_DEVICE_ID}
SOUL_DEVICE_ROLE=${SOUL_DEVICE_ROLE}
SOUL_PLATFORM=${SOUL_PLATFORM}
SOUL_ENVIRONMENT=${SOUL_ENVIRONMENT}
EOF
chown root:alloy /etc/soul-observability/collector.env
chmod 0640 /etc/soul-observability/collector.env
install -o root -g root -m 0644 "${SCRIPT_DIR}/alloy.service" /etc/systemd/system/alloy.service

/usr/local/bin/alloy validate /etc/soul-observability/config.alloy
systemctl daemon-reload
systemctl enable alloy
systemctl restart alloy
systemctl is-active --quiet alloy
rm -f "${ENV_FILE}" "${CA_FILE}"
echo "bounded Alloy metrics collector installed; journal ingestion remains disabled"
