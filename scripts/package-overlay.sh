#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -lt 2 ]]; then
  echo "Usage: scripts/package-overlay.sh output.zip file_or_dir [file_or_dir ...]"
  exit 1
fi

output="$1"
shift

rm -f "$output"
zip -r "$output" "$@"

echo "Created overlay: $output"
