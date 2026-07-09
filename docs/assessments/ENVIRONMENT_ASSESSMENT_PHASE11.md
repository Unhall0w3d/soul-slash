# Environment Assessment Phase 11

Phase 11 begins Soul's local environment assessment framework.

This phase is read-only.

Commands:

```bash
ruby bin/soul assess environment
ruby bin/soul assess environment --json
ruby bin/soul assess environment --updates
ruby bin/soul assess environment --updates --json
```

Supported package manager detection:

```text
pacman
yay
paru
flatpak
snap
nix
```

When `--updates` is supplied, Soul may run safe read-only checks:

```text
pacman -Qu
pacman -Qdtq
pacman -Qm
yay -Qua
paru -Qua
flatpak remote-ls --updates
flatpak uninstall --unused --dry-run
snap refresh --list
nix profile list
```

Soul must not apply updates, remove orphan packages, install packages, print secrets, scan unrelated user data, or change package manager state.

Future phases should add model inventory, GPU/VRAM assessment, service checks, storage/artifact hygiene, secrets hygiene, capability matrix, and improvement proposal generation.
