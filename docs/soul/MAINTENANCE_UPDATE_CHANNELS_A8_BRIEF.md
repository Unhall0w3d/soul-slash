# Maintenance Update Channels A8 Brief

```text
date: 2026-07-30
human_authorization: approved in the active development conversation
implementation_authorized: yes
risk: Class 1 read-only status normalization and Dashboard presentation
```

## Outcome

Make update evidence truthful and platform-specific across Guided Maintenance.
The Dashboard must name the package source that was actually assessed and must
not render unsupported or unqueried channels as zero updates.

## Contract

The existing additive `updates` object gains an ordered `channels` list. Each
channel contains:

- a stable identifier;
- a canonical package-manager label;
- a non-negative count when the query completed; and
- a bounded status distinguishing complete, unavailable, and not queried.

Unsupported channels are omitted. A count of zero means the channel was
actually queried successfully and returned no updates. The existing `native`,
`aur`, `flatpak`, `total`, and `freshness` fields remain during this slice for
private snapshot compatibility.

Built-in collectors expose:

- Atelier: pacman, AUR when an AUR helper is available, and Flatpak when at
  least one applicable installation can be queried;
- Forge, Warden, and qualified Foundry: APT only; and
- qualified or read-only Crucible: DNF5 only.

Detected but unassessed managers do not receive an update count. Future Snap,
Zypper, APK, Nix, or other collectors extend the same channel contract.

## Dashboard behavior

- Render only channels present in `updates.channels`.
- Replace `native` with the canonical manager label.
- Render unavailable evidence as unavailable, never zero.
- Keep inventory-only and provider-managed wording when updates were not
  queried.
- Canonicalize duplicate executable capabilities such as `apt` and `apt-get`
  into one presentation chip.
- Read older private snapshots safely through a conservative adapter-aware
  fallback until a fresh collection writes channels.

## Explicitly prohibited

- Inferring mutation authority from a package manager.
- Adding update commands or broadening existing collectors.
- Treating detection alone as completed update evidence.
- Changing maintenance or reboot gates.
- Persisting a new state store or adding background behavior.

## Acceptance

- [x] Supported collectors emit only applicable assessed channels.
- [x] Zero means a successful no-updates result.
- [x] Unavailable and not-queried states never render as zero.
- [x] The Dashboard uses canonical source names and omits unsupported channels.
- [x] Legacy snapshots degrade conservatively.
- [x] Existing fleet, discovery, device-control, and Fedora regressions pass.
- [x] Documentation and the private project tracker are synchronized.
