# Desktop updater source checkpoint

2026-10-14: copied byte-for-byte from the already exercised local recipe at
`~/Build/codex-desktop-local`. This is source preservation for a future CachyOS
bootstrap, not an installer run or a fresh release qualification.

| Source | SHA-256 |
| --- | --- |
| `codex-update` | `7574a15a1dd9da8c79afd32f9531599373a984cf834eb7c4b26faa93d962c2b7` |
| `PKGBUILD.in` | `2f9fc1da1182f424325963e6232c22d5fdd3d2e0b73cc2efbb77f223ae4fe07b` |
| `chatgpt-launcher.sh` | `d055179b71e8ba3daa73a8b0c19212fade7fa14571a88235a9f2feddfbb34d55` |
| `test-codex-update.sh` | `8d30a2ae8ecc7ac9eb15c1bf1ac8acacc5804e5849c7f87e53cbe6e3f5729245` |
| `README.md` | `7e692ea8906abcbf2892e5f4aac16fbc98937aef7bbe0ac7eb21c48a00865283` |

The canonical observed command is `codex-update`, not `update-codex`.
Its links under `~/Scripts` and `~/.local/bin` resolve to the Build directory.
The inspected shell configuration did not establish a reverse-name alias.
Do not restore just a dangling symlink. An optional compatibility alias can be
considered during the approved bootstrap; none was added in this checkpoint.

Shell syntax and the offline parser tests pass. `codex-update --check`, downloads,
`makepkg`, package installation, and application restart were not run here.
Generated PKGBUILD, downloaded proprietary binaries, package caches and rollback
packages are intentionally not included in this source checkpoint. Preserve a
known-good binary package separately in the approved recovery kit.

Use a writable copy in the operator's Build directory after checking the source
hashes; do not build as root or silently alter these preserved originals.
Read the original README's HTTPS/checksum versus signature trust limitation.
The launcher uses ordinary Wayland/X11 facilities and does not execute Omarchy
commands. The original README's Omarchy rollback notes are historical; do not
install Omarchy repositories or its old package on CachyOS as a default action.
In that historical README, `rollback/` refers to the original Build directory,
not this source-only copy; no rollback package or signature is stored here.

See [the restricted bootstrap handoff](../../docs/guides/CACHYOS_CODEX_BOOTSTRAP.md).
