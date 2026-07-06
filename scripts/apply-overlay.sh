#!/usr/bin/env bash
set -euo pipefail

overlay="${1:-}"

if [[ -z "$overlay" ]]; then
  echo "Usage: scripts/apply-overlay.sh /path/to/overlay.zip"
  exit 1
fi

if [[ ! -f "$overlay" ]]; then
  echo "Overlay not found: $overlay"
  exit 1
fi

echo "Applying overlay: $overlay"
unzip "$overlay"
echo "Overlay applied."
