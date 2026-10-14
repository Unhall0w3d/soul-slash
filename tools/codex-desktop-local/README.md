# Locally packaged ChatGPT Desktop

`codex-update` checks OpenAI's public Debian package index, compares its newest x86_64 `chatgpt` version with pacman, builds an Arch package with `makepkg`, and installs it with `sudo pacman -U` when the desktop app is closed. This is a **repackage of OpenAI's official binary**, not a source compilation or an OpenAI-supported Arch repository.

The local package retains the exact name `openai-codex-desktop`, `/usr/bin/chatgpt`, `/usr/bin/codex-desktop`, the desktop entry, and the existing Wayland/`codex-flags.conf` launcher behavior. `epoch=1` keeps routine `pacman -Syu`/Omarchy updates from replacing it with Omarchy's epoch-0 build; no `IgnorePkg` entry is needed. If Omarchy ever introduces its own epoch, review that collision.

From a regular terminal:

- `codex-update --check` checks versions without local changes.
- `codex-update --build-only` downloads and builds, leaving the installed app untouched.
- `codex-update` reuses a matching built package or builds one, then installs it. If ChatGPT is running, it **does not install**; close the app and run the same command again.
- `codex-update --rebuild` rebuilds the current upstream version, even if already locally installed.

The recipe lives here. The command is linked from `~/Scripts/codex-update` and `~/.local/bin/codex-update`. Downloads, build artifacts, and the generated `PKGBUILD` remain here for audit/rollback; the updater does not prune them. Run `./test-codex-update.sh` for parser checks and `bash -n codex-update chatgpt-launcher.sh test-codex-update.sh` for shell syntax.

Trust boundary: the updater retrieves the `Packages` index over HTTPS, validates the package/version/path/checksum shape, and `makepkg` verifies the downloaded `.deb` against its SHA-256. It does **not** verify the Debian repository's OpenPGP signature: a separate independently authenticated OpenAI signing key was not available in the inspected local/official documentation. Treat the HTTPS origin as the release authority and review an unexpected version jump before installing.

The last known working Omarchy-signed package and its signature are preserved under `rollback/` because `omarchy update` prunes the ordinary pacman cache. Do not remove them until the new app has passed chat and file-loading checks. A deliberate rollback would use `sudo pacman -U` on `rollback/openai-codex-desktop-26.915.31945-1-x86_64.pkg.tar.zst` from a terminal; this removes the local epoch and returns normal Omarchy update behavior. Neither the updater nor pacman clears `~/.config/Codex` or chat/profile state.
