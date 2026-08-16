#!/usr/bin/env bash
set -euo pipefail

if [[ ${EUID} -ne 0 ]]; then
  echo "finalize-credential-handoff.sh must run as root" >&2
  exit 1
fi

bootstrap=/var/lib/soul-observability/bootstrap-credentials.env
ingest=/var/lib/soul-observability/ingest-credential.env
[[ -f ${bootstrap} ]] || { echo "Grafana credential handoff is already finalized or unavailable" >&2; exit 1; }
[[ $(stat -c '%a' "${bootstrap}") == 600 ]] || { echo "bootstrap credential file must be mode 0600" >&2; exit 1; }

sed -i '/^GRAFANA_/d' "${bootstrap}"
grep -q '^INGEST_USER=' "${bootstrap}"
grep -q '^INGEST_PASSWORD=' "${bootstrap}"
mv "${bootstrap}" "${ingest}"
chmod 0600 "${ingest}"
echo "Grafana plaintext bootstrap credential removed; root-owned ingest enrollment credential retained"
