#!/usr/bin/bash
set -euo pipefail

readonly SOURCE_PATH="${1:-}"
readonly MAINTENANCE_USER="${2:-soul-maintenance}"
readonly HELPER_PATH="/usr/local/libexec/soul-debian-apt-maintenance"
readonly SUDOERS_PATH="/etc/sudoers.d/soul-debian-apt-maintenance"

fail_closed() { printf '%s\n' "$1" >&2; exit 64; }

[[ "$(id -u)" == "0" ]] || fail_closed "root authority is required"
[[ "$#" -le 2 ]] || fail_closed "argument count is invalid"
[[ -n "$SOURCE_PATH" && -f "$SOURCE_PATH" && ! -L "$SOURCE_PATH" ]] || fail_closed "reviewed helper source is required"
id "$MAINTENANCE_USER" >/dev/null 2>&1 || fail_closed "maintenance user must already exist"
command -v visudo >/dev/null 2>&1 || fail_closed "visudo is required"

install -d -o root -g root -m 0755 /usr/local/libexec
install -o root -g root -m 0755 "$SOURCE_PATH" "$HELPER_PATH"
digest="$(sha256sum "$HELPER_PATH" | awk '{print $1}')"
temporary="$(mktemp /etc/sudoers.d/.soul-debian-apt.XXXXXX)"
trap 'rm -f "$temporary"' EXIT
printf '%s ALL=(root) NOPASSWD: sha256:%s %s self-check, sha256:%s %s apt-upgrade, sha256:%s %s reboot\n' \
  "$MAINTENANCE_USER" "$digest" "$HELPER_PATH" "$digest" "$HELPER_PATH" "$digest" "$HELPER_PATH" >"$temporary"
chmod 0440 "$temporary"
visudo -cf "$temporary" >/dev/null
install -o root -g root -m 0440 "$temporary" "$SUDOERS_PATH"
visudo -cf "$SUDOERS_PATH" >/dev/null
"$HELPER_PATH" self-check
