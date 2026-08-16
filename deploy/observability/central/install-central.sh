#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "install-central.sh must run as root" >&2
  exit 1
fi

ENV_FILE=${1:-/root/soul-observability-a1.env}
[[ -f ${ENV_FILE} ]] || { echo "missing owner-private environment file" >&2; exit 1; }
[[ $(stat -c '%a' "${ENV_FILE}") == 600 ]] || { echo "environment file must be mode 0600" >&2; exit 1; }
# shellcheck disable=SC1090
source "${ENV_FILE}"
: "${OBSERVABILITY_FQDN:?missing OBSERVABILITY_FQDN}"
: "${GRAFANA_ADMIN_PASSWORD:?missing GRAFANA_ADMIN_PASSWORD}"
: "${INGEST_PASSWORD:?missing INGEST_PASSWORD}"
: "${SITE_LABEL:?missing SITE_LABEL}"
: "${SITE_LATITUDE:?missing SITE_LATITUDE}"
: "${SITE_LONGITUDE:?missing SITE_LONGITUDE}"
[[ ${OBSERVABILITY_FQDN} =~ ^[a-z0-9.-]+$ ]] || { echo "OBSERVABILITY_FQDN is invalid" >&2; exit 1; }
[[ ${GRAFANA_ADMIN_PASSWORD} =~ ^[A-Za-z0-9]{32,128}$ ]] || { echo "Grafana password must be 32-128 alphanumeric characters" >&2; exit 1; }
[[ ${INGEST_PASSWORD} =~ ^[A-Za-z0-9]{32,128}$ ]] || { echo "ingest password must be 32-128 alphanumeric characters" >&2; exit 1; }

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LOKI_VERSION=v3.7.6
LOKI_ZIP_SHA256=09d213427516581210bf39a5dca0b290722a3c17a623c5d6b654a85d6d5248ea

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends ca-certificates curl gpg unzip prometheus caddy apache2-utils

install -d -m 0755 /etc/apt/keyrings
curl -fsSL https://apt.grafana.com/gpg-full.key -o /etc/apt/keyrings/grafana.asc
chmod 0644 /etc/apt/keyrings/grafana.asc
printf '%s\n' 'deb [signed-by=/etc/apt/keyrings/grafana.asc] https://apt.grafana.com stable main' > /etc/apt/sources.list.d/grafana.list
apt-get update
apt-get install -y --no-install-recommends grafana

tmpdir=$(mktemp -d)
trap 'rm -rf "${tmpdir}"' EXIT
curl -fsSL "https://github.com/grafana/loki/releases/download/${LOKI_VERSION}/loki-linux-amd64.zip" -o "${tmpdir}/loki.zip"
printf '%s  %s\n' "${LOKI_ZIP_SHA256}" "${tmpdir}/loki.zip" | sha256sum -c -
unzip -q "${tmpdir}/loki.zip" -d "${tmpdir}"
install -m 0755 "${tmpdir}/loki-linux-amd64" /usr/local/bin/loki

getent group loki >/dev/null || groupadd --system loki
id loki >/dev/null 2>&1 || useradd --system --gid loki --home-dir /var/lib/loki --shell /usr/sbin/nologin loki
install -d -o loki -g loki -m 0750 /var/lib/loki /var/lib/loki/chunks /var/lib/loki/rules /var/lib/loki/compactor
install -d -o root -g loki -m 0750 /etc/loki
install -o root -g loki -m 0640 "${SCRIPT_DIR}/loki.yml" /etc/loki/loki.yml
install -o root -g root -m 0644 "${SCRIPT_DIR}/loki.service" /etc/systemd/system/loki.service

install -o root -g prometheus -m 0640 "${SCRIPT_DIR}/prometheus.yml" /etc/prometheus/prometheus.yml
install -d -o prometheus -g prometheus -m 0750 /var/lib/prometheus
install -d -m 0755 /etc/systemd/system/prometheus.service.d
cat > /etc/systemd/system/prometheus.service.d/soul-observability.conf <<'EOF'
[Service]
# Debian's packaged unit enables PrivateUsers, which cannot create its user
# namespace inside an unprivileged LXC. Preserve every other package hardening
# directive and disable only the incompatible namespace feature.
PrivateUsers=false
ExecStart=
ExecStart=/usr/bin/prometheus --config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path=/var/lib/prometheus/metrics2 --storage.tsdb.retention.time=30d --storage.tsdb.retention.size=28GB --web.enable-remote-write-receiver --web.listen-address=127.0.0.1:9090
EOF

install -d -o root -g grafana -m 0750 /etc/grafana/provisioning/datasources /etc/grafana/provisioning/dashboards
install -d -o grafana -g grafana -m 0750 /var/lib/grafana/dashboards
install -o root -g grafana -m 0640 "${SCRIPT_DIR}/grafana-datasources.yml" /etc/grafana/provisioning/datasources/soul.yml
install -o root -g grafana -m 0640 "${SCRIPT_DIR}/grafana-dashboard-provider.yml" /etc/grafana/provisioning/dashboards/soul.yml
"${SCRIPT_DIR}/render-dashboard.sh" "${ENV_FILE}" /var/lib/grafana/dashboards/fleet-overview.json
sed -i -E 's|^[; ]*http_addr *=.*|http_addr = 127.0.0.1|' /etc/grafana/grafana.ini
sed -i -E 's|^[; ]*http_port *=.*|http_port = 3000|' /etc/grafana/grafana.ini
sed -i -E 's|^[; ]*reporting_enabled *=.*|reporting_enabled = false|' /etc/grafana/grafana.ini
sed -i -E "s|^[; ]*admin_password *=.*|admin_password = ${GRAFANA_ADMIN_PASSWORD}|" /etc/grafana/grafana.ini

ingest_hash=$(printf '%s\n' "${INGEST_PASSWORD}" | htpasswd -nBi ingest | cut -d: -f2-)
sed -e "s/OBSERVABILITY_FQDN/${OBSERVABILITY_FQDN}/g" -e "s|INGEST_PASSWORD_HASH|${ingest_hash}|g" "${SCRIPT_DIR}/Caddyfile.template" > /etc/caddy/Caddyfile
chown root:caddy /etc/caddy/Caddyfile
chmod 0640 /etc/caddy/Caddyfile

systemctl daemon-reload
systemctl enable prometheus loki grafana-server caddy
systemctl restart prometheus loki grafana-server caddy
for unit in prometheus loki grafana-server caddy; do systemctl is-active --quiet "${unit}"; done

# Grafana's package may initialize its database before the reviewed config is
# installed. Converge the database-backed admin credential explicitly.
grafana cli --homepath /usr/share/grafana --config /etc/grafana/grafana.ini \
  admin reset-admin-password "${GRAFANA_ADMIN_PASSWORD}" >/dev/null

# The password has been persisted as Grafana's internal hash; remove plaintext config.
sed -i -E 's|^[; ]*admin_password *=.*|;admin_password =|' /etc/grafana/grafana.ini
install -d -m 0700 /var/lib/soul-observability
cat > /var/lib/soul-observability/bootstrap-credentials.env <<EOF
GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${GRAFANA_ADMIN_PASSWORD}
INGEST_USER=ingest
INGEST_PASSWORD=${INGEST_PASSWORD}
EOF
chmod 0600 /var/lib/soul-observability/bootstrap-credentials.env
rm -f "${ENV_FILE}"

cat > /var/lib/soul-observability/install-receipt.json <<EOF
{"schema_version":"soul.fleet-observability.central-install.a1.v1","loki_version":"${LOKI_VERSION}","metrics_retention":"30d","metrics_size":"28GB","logs_retention":"336h","journal_ingest":false,"mutation_authority":"none"}
EOF
chmod 0600 /var/lib/soul-observability/install-receipt.json
echo "central observability services installed; distribute Caddy's internal CA and owner-private ingest credential separately"
