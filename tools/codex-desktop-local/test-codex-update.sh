#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$(readlink -f -- "${BASH_SOURCE[0]}")")/codex-update"

sha_a=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
sha_b=bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
index=$(printf 'Package: chatgpt\nArchitecture: amd64\nVersion: 26.915.31945\nFilename: pool/main/c/chatgpt/chatgpt_26.915.31945_amd64.deb\nSHA256: %s\n\nPackage: chatgpt\nArchitecture: amd64\nVersion: 26.928.31416\nFilename: pool/main/c/chatgpt/chatgpt_26.928.31416_amd64.deb\nSHA256: %s\n' "$sha_a" "$sha_b")
actual=$(newest_release "$index")
expected="26.928.31416 $sha_b pool/main/c/chatgpt/chatgpt_26.928.31416_amd64.deb"
[[ "$actual" == "$expected" ]] || { printf 'wrong newest release: %s\n' "$actual" >&2; exit 1; }

bad_path=${index/chatgpt_26.928.31416_amd64.deb/other.deb}
if newest_release "$bad_path" >/dev/null; then
  printf 'accepted a mismatched upstream filename\n' >&2
  exit 1
fi

bad_sha=${index/$sha_b/invalid}
if newest_release "$bad_sha" >/dev/null; then
  printf 'accepted an invalid upstream checksum\n' >&2
  exit 1
fi

printf '%s\n' 'codex-update parser tests passed'
